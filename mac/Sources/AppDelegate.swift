// Gzowo Concierge for macOS - application lifecycle, main menu, bridge between the web UI and native pieces.
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController!
    private var status: StatusController!
    private let monitor = HostMonitor()
    private let model = AppModel()
    private let notch = NotchController()
    private let briefNotifier = BriefNotifier()
    private lazy var dictation = DictationController(hud: notch.model)
    private lazy var screenAgent = ScreenAgentController(hud: notch.model)
    private lazy var touchBarAssistant = TouchBarAssistant(model: notch.model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance()
        installMainMenu()
        windowController = MainWindowController(model: model)
        status = StatusController(delegate: self)
        windowController.web.onMessage = { [weak self] body in
            if body["type"] as? String == "live-view", let open = body["open"] as? Bool {
                Task { @MainActor in
                    self?.model.immersive = open
                    self?.windowController.web.view.evaluateJavaScript("document.documentElement.dataset.immersive = '\(open ? "1" : "")'; document.documentElement.style.setProperty('--lights', '\(open ? "78px" : "0px")')", completionHandler: nil)
                }
                return
            }
            guard body["type"] as? String == "state" else { return }
            if let live = body["live"] as? String { self?.monitor.setLive(live) }
            if let thread = body["thread"] as? String, !thread.isEmpty { Task { @MainActor in self?.model.adoptFromWeb(thread) } }
        }
        monitor.onChange = { [weak self] state in
            self?.status.update(state)
            Task { @MainActor in self?.model.apply(state); self?.notch.model.apply(state); self?.briefNotifier.check(ts: state.briefTs, text: state.briefText, thread: state.briefThread) }
        }
        notch.model.activeThread = { [weak self] in self?.model.activeID ?? "main" }
        notch.model.requestPoll = { [weak self] in self?.monitor.pollNow() }
        notch.model.onFinished = { [weak self] thread in
            Task { @MainActor in self?.windowController.web.call("openThread('\(thread)')") }
        }
        notch.onOpenApp = { [weak self] in self?.windowController.show() }
        notch.onOpenLive = { [weak self] in self?.openLive() }
        notch.model.openSettings = { [weak self] in self?.openSettings() }
        notch.model.quitApp = { NSApp.terminate(nil) }
        briefNotifier.onOpen = { [weak self] thread in
            self?.windowController.show()
            self?.model.select(thread)
        }
        briefNotifier.start()
        dictation.start()
        screenAgent.hiddenWindowNumbers = { [weak self] in self.map { [$0.notch.windowNumber] } ?? [] }
        notch.model.startAgent = { [weak self] task in self?.screenAgent.run(task: task) }
        notch.model.stopAgent = { [weak self] in self?.screenAgent.stop() }
        notch.model.answerAgent = { [weak self] yes in self?.screenAgent.answer(yes) }
        dictation.onAgentTask = { [weak self] task in self?.screenAgent.run(task: task) }
        notch.start()
        touchBarAssistant.start()
        status.setVisible(!notch.enabled)
        model.requestPoll = { [weak self] in self?.monitor.pollNow() }
        model.onNewThread = { [weak self] in self?.notch.model.agentHistory = []; self?.screenAgent.newSession() }
        model.requestRename = { [weak self] t in self?.promptRename(t) }
        monitor.start()
        windowController.show()
    }

    private func applyAppearance() {
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    @objc private func toggleTouchBar(_ sender: NSMenuItem) {
        touchBarAssistant.enabled.toggle()
        sender.state = touchBarAssistant.enabled ? .on : .off
    }

    @objc private func toggleDictation(_ sender: NSMenuItem) {
        dictation.enabled.toggle()
        sender.state = dictation.enabled ? .on : .off
    }

    @objc private func toggleNotch(_ sender: NSMenuItem) {
        notch.enabled.toggle()
        sender.state = notch.enabled ? .on : .off
        status.setVisible(!notch.enabled)
        if notch.enabled == false { NSApp.setActivationPolicy(.regular) }
    }

    @objc func newThread() { windowController.show(); Task { @MainActor in model.newThread() } }
    @objc func openToday() { windowController.show(); windowController.web.call("openView('today')") }
    @objc func openConnectors() { windowController.show(); windowController.web.call("openView('connectors')") }

    private func promptRename(_ t: ThreadInfo) {
        let alert = NSAlert()
        alert.messageText = "Zmień nazwę rozmowy"
        alert.addButton(withTitle: "Zapisz")
        alert.addButton(withTitle: "Anuluj")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = t.title
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            Task { @MainActor in model.rename(t, to: field.stringValue) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func toggleWindow() { windowController.toggle() }
    @objc func openWindow() { windowController.show() }

    @objc func openLive() {
        windowController.show()
        windowController.web.call("openLive()")
    }

    @objc func openSettings() {
        windowController.show()
        windowController.web.call("openSettings()")
    }

    @objc func reload() { windowController.web.reload() }

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "O Concierge", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = NSMenuItem(title: "Ustawienia…", action: #selector(openSettings), keyEquivalent: ","); settings.target = self
        app.addItem(settings)
        app.addItem(.separator())
        app.addItem(withTitle: "Ukryj Concierge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = NSMenuItem(title: "Ukryj pozostałe", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(others)
        app.addItem(withTitle: "Pokaż wszystkie", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Zakończ Concierge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edycja")
        edit.addItem(withTitle: "Cofnij", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Ponów", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Wytnij", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopiuj", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Wklej", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Zaznacz wszystko", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let threadItem = NSMenuItem(); main.addItem(threadItem)
        let thread = NSMenu(title: "Rozmowa")
        let fresh = NSMenuItem(title: "Nowa rozmowa", action: #selector(newThread), keyEquivalent: "n"); fresh.target = self
        thread.addItem(fresh)
        let liveItem = NSMenuItem(title: "Rozmowa na żywo", action: #selector(openLive), keyEquivalent: "l"); liveItem.target = self
        thread.addItem(liveItem)
        thread.addItem(.separator())
        let todayItem = NSMenuItem(title: "Dzisiaj", action: #selector(openToday), keyEquivalent: "t"); todayItem.target = self
        thread.addItem(todayItem)
        let connItem = NSMenuItem(title: "Konektory", action: #selector(openConnectors), keyEquivalent: "k"); connItem.keyEquivalentModifierMask = [.command, .shift]; connItem.target = self
        thread.addItem(connItem)
        threadItem.submenu = thread

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "Widok")
        let dock = NSMenuItem(title: "Dock w notchu", action: #selector(toggleNotch(_:)), keyEquivalent: ""); dock.target = self
        dock.state = notch.enabled ? .on : .off
        view.addItem(dock)
        let dict = NSMenuItem(title: "Dyktowanie (⌃⌥)", action: #selector(toggleDictation(_:)), keyEquivalent: ""); dict.target = self
        dict.state = dictation.enabled ? .on : .off
        view.addItem(dict)
        let tb = NSMenuItem(title: "Asystent na Touch Barze", action: #selector(toggleTouchBar(_:)), keyEquivalent: ""); tb.target = self
        tb.state = touchBarAssistant.enabled ? .on : .off
        view.addItem(tb)
        view.addItem(.separator())
        let reload = NSMenuItem(title: "Przeładuj", action: #selector(reload), keyEquivalent: "r"); reload.target = self
        view.addItem(reload)
        view.addItem(.separator())
        let full = NSMenuItem(title: "Pełny ekran", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]
        view.addItem(full)
        viewItem.submenu = view

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "Okno")
        window.addItem(withTitle: "Zamknij", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Zwiń", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Powiększ", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = window
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }
}
