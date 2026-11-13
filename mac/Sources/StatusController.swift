// Gzowo Concierge for macOS - menu bar item: orb plus live CPU, GPU and RAM, click opens the control panel, right click the menu.
import AppKit

@MainActor final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var stats: StatsSnapshot?
    var onClick: (NSStatusBarButton) -> Void = { _ in }
    var showStats = true
    private weak var delegate: AppDelegate?
    private var state = HostState()
    private var animator: Timer?
    private var phase: CGFloat = 0

    init(delegate: AppDelegate) {
        self.delegate = delegate
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Concierge"
        }
        redraw()
    }

    func setVisible(_ visible: Bool) { item.isVisible = visible }

    var button: NSStatusBarButton? { item.button }

    func update(_ next: HostState) {
        state = next
        let active = next.online && (next.busy || next.live == "thinking" || next.live == "speaking")
        if active && animator == nil {
            animator = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.phase = (self.phase + 0.018).truncatingRemainder(dividingBy: 1)
                self.redraw()
            }
        } else if !active, let t = animator {
            t.invalidate(); animator = nil
        }
        redraw()
        var tip = "Concierge"
        if !next.online { tip += ": host nie odpowiada" }
        else if next.pending > 0 { tip += ": czeka na zgodę (\(next.pending))" }
        else if next.busy { tip += ": pracuje" }
        item.button?.toolTip = tip
    }

    func setStats(_ s: StatsSnapshot?) {
        stats = s
        redraw()
    }

    private func redraw() {
        let orb = OrbIcon.image(for: state, phase: phase)
        guard showStats, let stats else { item.button?.image = orb; return }
        let text = MenuBarStats.image(stats)
        let img = NSImage(size: NSSize(width: orb.size.width + 7 + text.size.width, height: 22), flipped: false) { _ in
            orb.draw(in: NSRect(x: 0, y: (22 - orb.size.height) / 2, width: orb.size.width, height: orb.size.height))
            text.draw(in: NSRect(x: orb.size.width + 7, y: 0, width: text.size.width, height: 22))
            return true
        }
        img.isTemplate = true
        item.button?.image = img
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            item.menu = buildMenu()
            sender.performClick(nil)
            item.menu = nil
        } else {
            onClick(sender)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let status: String
        if !state.online { status = "Host nie odpowiada" }
        else if state.pending > 0 { status = state.pending == 1 ? "Czeka 1 prośba o zgodę" : "Czeka \(state.pending) prośby o zgodę" }
        else if state.busy { status = "Pracuję nad zadaniem" }
        else { status = "Gotowy" }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.image = NSImage(systemSymbolName: state.online ? "circle.fill" : "moon.zzz", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 9, weight: .regular))
        menu.addItem(header)
        menu.addItem(.separator())
        let statsItem = NSMenuItem(title: "Statystyki w pasku menu", action: #selector(toggleStats), keyEquivalent: "")
        statsItem.target = self
        statsItem.state = showStats ? .on : .off
        menu.addItem(statsItem)
        menu.addItem(.separator())
        menu.addItem(item("Nowa rozmowa", "square.and.pencil", #selector(AppDelegate.newThread), "n"))
        menu.addItem(item("Otwórz Concierge", "macwindow", #selector(AppDelegate.openWindow), "o"))
        menu.addItem(item("Rozmowa na żywo", "waveform", #selector(AppDelegate.openLive), "l"))
        menu.addItem(item("Ustawienia", "gearshape", #selector(AppDelegate.openSettings), ","))
        menu.addItem(.separator())
        menu.addItem(item("Przeładuj", "arrow.clockwise", #selector(AppDelegate.reload), "r"))
        menu.addItem(item("Zakończ Concierge", "power", #selector(NSApplication.terminate(_:)), "q", target: NSApp))
        return menu
    }

    var onStatsToggle: (Bool) -> Void = { _ in }

    @objc private func toggleStats() {
        showStats.toggle()
        onStatsToggle(showStats)
        redraw()
    }

    private func item(_ title: String, _ symbol: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = target ?? delegate
        mi.keyEquivalentModifierMask = [.command]
        mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return mi
    }
}
