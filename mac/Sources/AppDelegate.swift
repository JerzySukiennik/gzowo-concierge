// Gzowo Concierge for macOS - application lifecycle, main menu, bridge between the web UI and native pieces.
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController!
    private var status: StatusController!
    private let monitor = HostMonitor()
    private let model = AppModel()

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
            Task { @MainActor in self?.model.apply(state) }
        }
        model.requestPoll = { [weak self] in self?.monitor.pollNow() }
        model.requestRename = { [weak self] t in self?.promptRename(t) }
        monitor.start()
        windowController.show()
    }

    private func applyAppearance() {
        switch UserDefaults.standard.string(forKey: "appearance") ?? "light" {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "system": NSApp.appearance = nil
        default: NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    @objc private func setAppearance(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String ?? "light", forKey: "appearance")
        applyAppearance()
        windowController.web.reload()
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
        let look = NSMenu(title: "Wygląd")
        for (title, key) in [("Jasny", "light"), ("Ciemny", "dark"), ("Systemowy", "system")] {
            let mi = NSMenuItem(title: title, action: #selector(setAppearance(_:)), keyEquivalent: ""); mi.target = self; mi.representedObject = key
            look.addItem(mi)
        }
        let lookItem = NSMenuItem(title: "Wygląd", action: nil, keyEquivalent: ""); lookItem.submenu = look
        view.addItem(lookItem)
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
