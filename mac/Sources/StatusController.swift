// Gzowo Concierge for macOS - menu bar item: animated orb, click to toggle the window, right click for the menu.
import AppKit

@MainActor final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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

    private func redraw() {
        item.button?.image = OrbIcon.image(for: state, phase: phase)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            item.menu = buildMenu()
            sender.performClick(nil)
            item.menu = nil
        } else {
            delegate?.toggleWindow()
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
        menu.addItem(item("Nowa rozmowa", "square.and.pencil", #selector(AppDelegate.newThread), "n"))
        menu.addItem(item("Otwórz Concierge", "macwindow", #selector(AppDelegate.openWindow), "o"))
        menu.addItem(item("Rozmowa na żywo", "waveform", #selector(AppDelegate.openLive), "l"))
        menu.addItem(item("Ustawienia", "gearshape", #selector(AppDelegate.openSettings), ","))
        menu.addItem(.separator())
        menu.addItem(item("Przeładuj", "arrow.clockwise", #selector(AppDelegate.reload), "r"))
        menu.addItem(item("Zakończ Concierge", "power", #selector(NSApplication.terminate(_:)), "q", target: NSApp))
        return menu
    }

    private func item(_ title: String, _ symbol: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = target ?? delegate
        mi.keyEquivalentModifierMask = [.command]
        mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return mi
    }
}
