// Gzowo Concierge for macOS - application lifecycle, main menu, bridge between the web UI and native pieces.
import AppKit
import Combine

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController!
    private var status: StatusController!
    private let monitor = HostMonitor()
    private let model = AppModel()
    private let notch = NotchController()
    private let briefNotifier = BriefNotifier()
    private let lidFold = LidFoldController()
    private let macLink = MacLink()
    private lazy var dictation = DictationController(hud: notch.model)
    private lazy var screenAgent = ScreenAgentController(hud: notch.model)
    private lazy var touchBarAssistant = TouchBarAssistant(model: notch.model)
    private let levels = SystemLevels()
    private let media = MediaController()
    private var mediaSink: AnyCancellable?
    private let control = ControlPanelController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["CONCIERGE_BASE"] == nil, ProcessInfo.processInfo.environment["CONCIERGE_TB_TEST"] == nil,
              let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else { return }
        if !LoginAgent.launchedAsIsland { existing.activate(options: []) }
        exit(0)
    }

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
            Task { @MainActor in self?.control.hub.hostLine = !state.online ? "Host nie odpowiada" : (state.pending > 0 ? "Czeka na Twoją zgodę" : (state.busy ? "Pracuję…" : "Gotowy")); self?.control.hub.avatar = state.avatarShape }
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
        if let fake = ProcessInfo.processInfo.environment["CONCIERGE_FAKE_AGENT"] {
            notch.model.agent = fake == "finished"
                ? AgentState(finished: true, ok: true, summary: "Sformatowałem nagłówek: pogrubiłem tylko tytuł dokumentu i odznaczyłem tekst.")
                : AgentState(active: true, step: 2, total: 5, narration: "Wpisuję imię i nazwisko")
        }
        touchBarAssistant.openLive = { [weak self] in self?.openLive() }
        touchBarAssistant.start()
        startLiveActivities()
        if ProcessInfo.processInfo.environment["CONCIERGE_TB_TEST"] == nil { lidFold.start() }
        macLink.onShow = { [weak self] thread, url in
            guard let self else { return }
            self.windowController.show()
            self.model.select(thread)
            if let url { NSWorkspace.shared.open(url) }
        }
        macLink.start()
        NotificationCenter.default.addObserver(forName: .conciergePolicyChanged, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.touchBarAssistant.policyChanged() } }
        status.setVisible(true)
        startControlPanel()
        model.requestPoll = { [weak self] in self?.monitor.pollNow() }
        model.onNewThread = { [weak self] in self?.notch.model.agentHistory = []; self?.screenAgent.newSession() }
        model.requestRename = { [weak self] t in self?.promptRename(t) }
        monitor.start()
        LoginAgent.sync()
        if !(LoginAgent.launchedAsIsland && notch.enabled) { windowController.show() }
    }

    private func startControlPanel() {
        status.showStats = control.menuStatsEnabled
        status.onClick = { [weak self] button in self?.control.toggle(from: button) }
        status.onStatsToggle = { [weak self] on in self?.control.menuStatsEnabled = on; if !on { self?.status.setStats(nil) } }
        control.onStats = { [weak self] s in guard let self, self.status.showStats else { return }; self.status.setStats(s) }
        control.hub.openApp = { [weak self] in self?.windowController.show() }
        control.hub.openSettings = { [weak self] in self?.openSettings() }
        control.hub.keyboard.lockTouchBar = { [weak self] on in self?.touchBarAssistant.lock(on) }
        control.start()
        if ProcessInfo.processInfo.environment["CONCIERGE_TB_TEST"] != nil {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.panel-test"), object: nil, queue: .main) { [weak self] n in
                let cmd = (n.object as? String) ?? ""
                Task { @MainActor in self?.panelTest(cmd) }
            }
        }
    }

    private func panelTest(_ cmd: String) {
        switch cmd {
        case "open": if let b = status.button { control.show(from: b) }
        case "close": control.hide()
        case "stop": control.hub.go(.stop)
        case "startup": control.hub.go(.startup)
        case "clean": control.hub.go(.clean)
        case "uninstall": control.hub.go(.uninstall)
        case "updates": control.hub.go(.updates)
        case "main": control.hub.go(.main)
        case let c where c.hasPrefix("vol:"):
            let parts = c.split(separator: ":")
            if parts.count == 3, let app = control.hub.mixer.apps.first(where: { $0.name == String(parts[1]) }), let v = Float(parts[2]) { control.hub.mixer.setVolume(app, v) }
            print("mixer:", control.hub.mixer.debugLine()); fflush(stdout)
        case "mixer":
            control.hub.mixer.refresh()
            print("mixer:", control.hub.mixer.debugLine()); fflush(stdout)
        case let c where c.hasPrefix("leftovers:"):
            let name = String(c.dropFirst(10))
            if let app = Housekeeping.installedApps().first(where: { $0.name == name }) { print("leftovers \(name):", Housekeeping.leftovers(for: app).map { "\($0.path) \($0.size)" }); fflush(stdout) }
        case "kbclean": control.hub.keyboard.start()
        case "kbstop":
            print("keyboard presses:", control.hub.keyboard.presses, "tap:", control.hub.keyboard.tapState); fflush(stdout)
            control.hub.keyboard.stop()
        case "procs":
            control.hub.procs.scan()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { print("stop targets:", self.control.hub.procs.targets.map { "\($0.kind) \($0.name) \($0.checked)" }); fflush(stdout) }
        default: break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        control.hub.mixer.stopAll()
        control.hub.keyboard.stop()
    }

    private func startLiveActivities() {
        let island = notch.model
        levels.onChange = { [weak self] e in Task { @MainActor in self?.notch.model.showLevel(e) } }
        levels.onMediaKey = { [weak self] in Task { @MainActor in try? await Task.sleep(for: .milliseconds(350)); self?.notch.model.peekMedia() } }
        levels.start()
        media.onChange = { [weak self] track, play in
            guard let self else { return }
            island.setMedia(self.media.info, art: self.media.art, icon: self.media.appIcon)
            if track && self.media.info.playing { self.notch.model.peekMedia(for: 3.2) } else if play && !track { self.notch.model.peekMedia() }
        }
        mediaSink = Publishers.CombineLatest3(media.$info, media.$art, media.$appIcon).sink { info, art, icon in
            Task { @MainActor in island.setMedia(info, art: art, icon: icon) }
        }
        island.mediaCommand = { [weak self] cmd in self?.media.send(cmd) }
        island.mediaSeek = { [weak self] s in self?.media.seek(to: s) }
        media.start()
    }

    @objc private func toggleLevels(_ sender: NSMenuItem) {
        levels.enabled.toggle()
        sender.state = levels.enabled ? .on : .off
    }

    @objc private func toggleMedia(_ sender: NSMenuItem) {
        media.enabled.toggle()
        sender.state = media.enabled ? .on : .off
    }

    private func applyAppearance() {
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    @objc private func toggleLidFold(_ sender: NSMenuItem) {
        lidFold.enabled.toggle()
        sender.state = lidFold.enabled ? .on : .off
    }

    @objc private func showLidFold() { lidFold.playDemo() }

    @objc private func toggleLoginStart(_ sender: NSMenuItem) {
        LoginAgent.enabled.toggle()
        sender.state = LoginAgent.enabled ? .on : .off
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
        let lv = NSMenuItem(title: "Głośność i jasność na wyspie", action: #selector(toggleLevels(_:)), keyEquivalent: ""); lv.target = self
        lv.state = levels.enabled ? .on : .off
        view.addItem(lv)
        let md = NSMenuItem(title: "Teraz grane na wyspie", action: #selector(toggleMedia(_:)), keyEquivalent: ""); md.target = self
        md.state = media.enabled ? .on : .off
        view.addItem(md)
        let tb = NSMenuItem(title: "Asystent na Touch Barze", action: #selector(toggleTouchBar(_:)), keyEquivalent: ""); tb.target = self
        tb.state = touchBarAssistant.enabled ? .on : .off
        view.addItem(tb)
        let ls = NSMenuItem(title: "Uruchamiaj przy logowaniu (sama wyspa)", action: #selector(toggleLoginStart(_:)), keyEquivalent: ""); ls.target = self
        ls.state = LoginAgent.enabled ? .on : .off
        view.addItem(ls)
        if lidFold.available {
            let lf = NSMenuItem(title: "Animacja klapy", action: #selector(toggleLidFold(_:)), keyEquivalent: ""); lf.target = self
            lf.state = lidFold.enabled ? .on : .off
            view.addItem(lf)
            let ld = NSMenuItem(title: "Pokaż animację klapy", action: #selector(showLidFold), keyEquivalent: ""); ld.target = self
            view.addItem(ld)
        }
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
