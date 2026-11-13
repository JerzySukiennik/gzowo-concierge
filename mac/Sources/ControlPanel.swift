// Gzowo Concierge for macOS - the menu bar panel: closed-lid mode, screen off, keyboard cleaning, live system monitor, memory hogs, per-app volume, stop everything, startup items and housekeeping.
import AppKit
import Combine
import SwiftUI

final class ControlPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum PanelPage: Equatable { case main, stop, startup, clean, uninstall, updates }

@MainActor
final class ControlHub: ObservableObject {
    let stats = SystemStats()
    let power = PowerControl()
    let procs = ProcessControl()
    let startup = StartupItems()
    let house = Housekeeping()
    let mixer = AppMixer()
    let keyboard = KeyboardClean()
    @Published var page: PanelPage = .main
    @Published var forward = true
    @Published var open = false
    @Published var appIcon: NSImage?
    @Published var hostLine = "Gotowy"
    @Published var avatar = "circle"
    var openApp: () -> Void = {}
    var openSettings: () -> Void = {}
    var close: () -> Void = {}
    private var bag = Set<AnyCancellable>()

    init() {
        for o in [stats.objectWillChange, power.objectWillChange, procs.objectWillChange, startup.objectWillChange, house.objectWillChange, mixer.objectWillChange, keyboard.objectWillChange] as [ObservableObjectPublisher] {
            o.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
    }

    func go(_ p: PanelPage) {
        forward = p != .main
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { page = p }
        switch p {
        case .stop: procs.scan(); startup.scan()
        case .startup: startup.scan()
        case .clean: house.scanCaches()
        case .uninstall: if house.apps.isEmpty { house.loadApps() }
        case .updates: house.checkUpdates()
        case .main: break
        }
    }
}

@MainActor
final class ControlPanelController {
    let hub = ControlHub()
    private var panel: ControlPanelWindow?
    private var monitors: [Any] = []
    private weak var anchor: NSStatusBarButton?
    private let width: CGFloat = 372
    var onStats: (StatsSnapshot) -> Void = { _ in }

    var menuStatsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "menuBarStats") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "menuBarStats"); idle() }
    }

    func start() {
        hub.close = { [weak self] in self?.hide() }
        hub.stats.onTick = { [weak self] s in self?.onStats(s) }
        hub.mixer.start()
        hub.house.startSchedule()
        idle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.hub.house.checkUpdates() }
    }

    private func idle() {
        if menuStatsEnabled { hub.stats.run(every: 3, detailed: false) } else { hub.stats.stop() }
    }

    var isOpen: Bool { panel?.isVisible ?? false }

    func toggle(from button: NSStatusBarButton) { isOpen ? hide() : show(from: button) }

    func show(from button: NSStatusBarButton) {
        anchor = button
        let p = panel ?? makePanel()
        panel = p
        hub.page = .main
        hub.power.refresh()
        hub.stats.run(every: 1, detailed: true)
        hub.mixer.setPanelOpen(true)
        hub.startup.scan()
        if hub.house.caches.isEmpty { hub.house.scanCaches() }
        hub.house.checkUpdates()
        place(p)
        p.alphaValue = 0
        p.orderFrontRegardless()
        p.makeKey()
        hub.open = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { hub.open = true }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.16; p.animator().alphaValue = 1 }
        installMonitors()
    }

    func hide() {
        guard let p = panel, p.isVisible else { return }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        withAnimation(.easeIn(duration: 0.12)) { hub.open = false }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.14; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
        hub.mixer.setPanelOpen(false)
        idle()
    }

    private func makePanel() -> ControlPanelWindow {
        let p = ControlPanelWindow(contentRect: NSRect(x: 0, y: 0, width: width + 24, height: 600), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.hidesOnDeactivate = false
        let root = ControlPanelView(hub: hub, width: width, maxHeight: maxHeight) { [weak self] h in self?.resize(h) }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        p.contentView = host
        return p
    }

    private var maxHeight: CGFloat {
        let s = anchor?.window?.screen ?? NSScreen.main
        return max(420, (s?.visibleFrame.height ?? 900) - 24)
    }

    private var contentHeight: CGFloat = 640

    private func resize(_ h: CGFloat) {
        contentHeight = min(h, maxHeight - 24)
        if let p = panel { place(p) }
    }

    private func place(_ p: NSPanel) {
        guard let button = anchor, let win = button.window else { return }
        let r = win.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = win.screen ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let w = width + 24, h = contentHeight + 24
        var x = r.midX - w / 2
        x = min(max(vf.minX + 4, x), vf.maxX - w - 4)
        p.setFrame(NSRect(x: x, y: vf.maxY - h + 6, width: w, height: h), display: true)
    }

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in Task { @MainActor in self?.hide() } }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] e in
            guard let self, e.keyCode == 53 else { return e }
            if self.hub.page != .main { self.hub.go(.main) } else { self.hide() }
            return nil
        }) { monitors.append(m) }
    }
}

// MARK: views

private let ink = Color.white
private let card = Color.white.opacity(0.07)
private let cardHi = Color.white.opacity(0.11)
private let amber = Color(red: 1, green: 0.72, blue: 0.28)
private let errorRed = Color(red: 1, green: 0.45, blue: 0.43)

struct ControlPanelView: View {
    @ObservedObject var hub: ControlHub
    var width: CGFloat
    var maxHeight: CGFloat
    var onHeight: (CGFloat) -> Void
    @State private var mainHeight: CGFloat = 640

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.085))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
            ZStack(alignment: .top) {
                if hub.page == .main {
                    ScrollView(showsIndicators: false) {
                        MainPage(hub: hub)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                                mainHeight = h
                                onHeight(h)
                            }
                    }
                    .scrollDisabled(mainHeight <= maxHeight - 24)
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    SubPage(hub: hub)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(width: width, height: min(mainHeight, maxHeight - 24))
        .scaleEffect(hub.open ? 1 : 0.96, anchor: .top)
        .offset(y: hub.open ? 0 : -6)
        .padding(12)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct MainPage: View {
    @ObservedObject var hub: ControlHub

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            tiles
            MonitorGrid(hub: hub, stats: hub.stats)
            MemoryList(hub: hub, stats: hub.stats)
            MixerList(mixer: hub.mixer)
            VStack(spacing: 0) {
                NavRow(icon: "stop.circle", title: "Zatrzymaj wszystko", value: "") { hub.go(.stop) }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 44)
                NavRow(icon: "power", title: "Uruchamiane przy starcie", value: hub.startup.items.isEmpty ? "" : "\(hub.startup.activeCount)") { hub.go(.startup) }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 44)
                NavRow(icon: "sparkles", title: "Porządki", value: hub.house.scanning && hub.house.caches.isEmpty ? "…" : Fmt.bytes(Double(hub.house.cacheTotal))) { hub.go(.clean) }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 44)
                NavRow(icon: "trash", title: "Odinstaluj apkę", value: "") { hub.go(.uninstall) }
                Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 44)
                NavRow(icon: "arrow.down.circle", title: "Aktualizacje apek", value: hub.house.checkingUpdates ? "…" : (hub.house.updates.isEmpty ? "brak" : "\(hub.house.updates.count)"), accent: !hub.house.updates.isEmpty) { hub.go(.updates) }
            }
            .background(card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 11) {
            NotchBot(kind: hub.avatar, color: "white", size: 30, busy: false, alert: false, look: .zero, blink: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("Concierge").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                Text(hub.hostLine).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            CircleButton(symbol: "macwindow", help: "Otwórz Concierge") { hub.close(); hub.openApp() }
            CircleButton(symbol: "gearshape", help: "Ustawienia") { hub.close(); hub.openSettings() }
        }
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            Tile(icon: "laptopcomputer", title: "Klapa", subtitle: hub.power.working ? "Przełączam…" : (hub.power.lidMode ? "Działa po zamknięciu" : "Usypia po zamknięciu"), on: hub.power.lidMode) { hub.power.toggleLid() }
            Tile(icon: "display", title: "Ekran", subtitle: "Wyłącz teraz", on: false) { hub.close(); hub.power.screenOff() }
            Tile(icon: "keyboard", title: "Klawiatura", subtitle: "Czyszczenie", on: hub.keyboard.active) { hub.close(); hub.keyboard.start() }
        }
        .overlay(alignment: .bottom) {
            if !hub.power.problem.isEmpty { Text(hub.power.problem).font(.system(size: 11)).foregroundStyle(errorRed).offset(y: 18) }
        }
    }
}

private struct Tile: View {
    var icon: String
    var title: String
    var subtitle: String
    var on: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 19, weight: .regular)).frame(height: 24)
                    .contentTransition(.symbolEffect(.replace))
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).opacity(0.62).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(on ? Color.black : ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(on ? Color.white : (hover ? cardHi : card), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: on)
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .onHover { hover = $0 }
    }
}

private struct CircleButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12.5, weight: .medium)).foregroundStyle(ink)
                .frame(width: 30, height: 30).background(card, in: Circle())
        }
        .buttonStyle(PressStyle()).help(help).accessibilityLabel(help)
    }
}

private struct NavRow: View {
    var icon: String
    var title: String
    var value: String
    var accent = false
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 13.5, weight: .medium)).frame(width: 20)
                Text(title).font(.system(size: 13))
                Spacer()
                if !value.isEmpty {
                    Text(value).font(.system(size: 12, weight: accent ? .semibold : .regular).monospacedDigit()).foregroundStyle(accent ? amber : .white.opacity(0.5))
                }
                Image(systemName: "chevron.right").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 14).frame(height: 40)
            .background(hover ? Color.white.opacity(0.05) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct Spark: View {
    var values: [Double]
    var maxValue: Double? = nil

    var body: some View {
        GeometryReader { g in
            let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
            Path { p in
                guard values.count > 1 else { return }
                let step = g.size.width / CGFloat(max(1, 39))
                let start = g.size.width - step * CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: start + step * CGFloat(i), y: g.size.height * (1 - CGFloat(min(1, v / top))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
            .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 14)
    }
}

private struct Metric: View {
    var title: String
    var value: String
    var extra: String = ""
    var spark: [Double] = []
    var sparkMax: Double? = nil
    var bar: Double? = nil
    var barColor: Color = .white
    var lines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            if lines.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(ink).contentTransition(.numericText())
                    if !extra.isEmpty { Text(extra).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.6)) }
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                ForEach(lines, id: \.self) { l in Text(l).font(.system(size: 11.5, weight: .medium).monospacedDigit()).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8) }
            }
            Spacer(minLength: 0)
            if let bar {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(barColor).frame(width: max(4, g.size.width * min(1, bar)))
                    }
                }
                .frame(height: 5)
            } else if !spark.isEmpty {
                Spark(values: spark, maxValue: sparkMax)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MonitorGrid: View {
    @ObservedObject var hub: ControlHub
    @ObservedObject var stats: SystemStats

    var body: some View {
        let s = stats.snap
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Metric(title: "CPU", value: Fmt.percent(s.cpu), extra: Fmt.temp(s.cpuTemp), spark: s.cpuHistory, sparkMax: 1)
                Metric(title: "GPU", value: Fmt.percent(s.gpu), extra: Fmt.temp(s.gpuTemp), spark: s.gpuHistory, sparkMax: 1)
                Metric(title: "RAM", value: Fmt.percent(s.memFraction), extra: Fmt.bytes(Double(s.memUsed)), bar: s.memFraction, barColor: s.pressure >= 2 ? amber : .white)
            }
            HStack(spacing: 8) {
                Metric(title: "Wentylatory", value: s.fans.isEmpty ? "–" : "\(Int((s.fans.max() ?? 0).rounded()))", extra: s.fans.isEmpty ? "" : "obr/min", spark: s.fanHistory, sparkMax: max(s.fanMax, 1))
                Metric(title: "Dysk", value: Fmt.bytes(Double(s.diskFree), decimals: false), extra: "wolne", spark: s.diskHistory)
                Metric(title: "Sieć", value: "", spark: s.netHistory, lines: ["↓ " + Fmt.rate(s.netDown), "↑ " + Fmt.rate(s.netUp)])
            }
            if let b = s.battery { BatteryRow(b: b, power: s.power) }
        }
    }
}

private struct BatteryRow: View {
    var b: Battery
    var power: Double?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.2).frame(width: 30, height: 15)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(b.percent <= 15 && !b.plugged ? errorRed : Color.white).frame(width: max(2, 26 * CGFloat(b.percent) / 100), height: 11).padding(.leading, 2)
                if b.charging { Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.black).frame(width: 30) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Bateria").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 6) {
                    Text("\(b.percent)%").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(ink)
                    if let p = power, p > 0.5 { Text("\(Int(p.rounded())) W").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.6)) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    if b.charging { Circle().fill(amber).frame(width: 6, height: 6) }
                    Text(status).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.75))
                }
                if let c = b.cycles { Text("\(c) cykli" + (b.health.map { ", kondycja \($0)%" } ?? "")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var status: String {
        if b.charging { return "Ładowanie" }
        if b.plugged { return "Zasilacz" }
        if let m = b.minutesLeft { return "Na baterii, \(m / 60):" + String(format: "%02d", m % 60) }
        return "Na baterii"
    }
}

private struct MemoryList: View {
    @ObservedObject var hub: ControlHub
    @ObservedObject var stats: SystemStats

    var body: some View {
        let top = Array(stats.apps.filter { $0.id != "system" }.prefix(4))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                SectionTitle("Pamięć")
                ForEach(top) { app in MemoryRow(hub: hub, app: app, icon: stats.icon(for: app), top: Double(top.first?.bytes ?? 1)) }
            }
        }
    }
}

private struct MemoryRow: View {
    @ObservedObject var hub: ControlHub
    var app: AppUsage
    var icon: NSImage
    var top: Double
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            Text(app.name).font(.system(size: 12.5)).foregroundStyle(ink).lineLimit(1).frame(width: 118, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Color.white.opacity(0.75)).frame(width: max(4, g.size.width * Double(app.bytes) / max(top, 1)))
                }
            }
            .frame(height: 4)
            if hover && app.bundle?.path != Bundle.main.bundlePath {
                Button { hub.procs.quit(app) } label: {
                    Text("Zakończ").font(.system(size: 11, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 9).frame(height: 20).background(Color.white, in: Capsule())
                }
                .buttonStyle(PressStyle()).frame(width: 64, alignment: .trailing)
            } else {
                Text(Fmt.bytes(Double(app.bytes))).font(.system(size: 11.5, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.65)).frame(width: 64, alignment: .trailing)
            }
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

private struct MixerList: View {
    @ObservedObject var mixer: AppMixer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Dźwięk")
            HStack(spacing: 10) {
                Button { mixer.toggleMute() } label: {
                    Image(systemName: mixer.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).frame(width: 20)
                }
                .buttonStyle(PressStyle())
                Text("Wszystko").font(.system(size: 12.5)).foregroundStyle(ink).frame(width: 90, alignment: .leading)
                VolumeSlider(value: mixer.muted ? 0 : mixer.master) { mixer.setMaster($0) }
                Text(mixer.muted ? "wycisz." : "\(Int((mixer.master * 100).rounded()))%").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.55)).frame(width: 42, alignment: .trailing)
            }
            ForEach(mixer.apps) { app in
                HStack(spacing: 10) {
                    Image(nsImage: app.bundle.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)).resizable().frame(width: 20, height: 20)
                        .opacity(app.playing ? 1 : 0.5)
                    Text(app.name).font(.system(size: 12.5)).foregroundStyle(ink.opacity(app.playing ? 1 : 0.6)).lineLimit(1).frame(width: 90, alignment: .leading)
                    VolumeSlider(value: app.volume) { mixer.setVolume(app, $0) }
                    Text("\(Int((app.volume * 100).rounded()))%").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.55)).frame(width: 42, alignment: .trailing)
                }
            }
            if mixer.apps.isEmpty { Text("Żadna apka teraz nie gra.").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.4)) }
            if !mixer.problem.isEmpty { Text(mixer.problem).font(.system(size: 11)).foregroundStyle(errorRed) }
        }
    }
}

private struct VolumeSlider: View {
    var value: Float
    var onChange: (Float) -> Void
    @State private var drag: Float?

    var body: some View {
        GeometryReader { g in
            let v = CGFloat(drag ?? value)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 5)
                Capsule().fill(Color.white).frame(width: max(5, g.size.width * v), height: 5)
                Circle().fill(Color.white).frame(width: 14, height: 14).shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: max(0, min(g.size.width - 14, g.size.width * v - 7)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in let x = Float(max(0, min(1, d.location.x / g.size.width))); drag = x; onChange(x) }
                .onEnded { _ in drag = nil })
        }
        .frame(height: 18)
    }
}

private struct SectionTitle: View {
    var text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7)) }
}

// MARK: sub pages

private struct SubPage: View {
    @ObservedObject var hub: ControlHub

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { hub.go(.main) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).frame(width: 28, height: 28).background(card, in: Circle())
                }
                .buttonStyle(PressStyle())
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            switch hub.page {
            case .stop: StopPage(hub: hub, procs: hub.procs)
            case .startup: StartupPage(startup: hub.startup)
            case .clean: CleanPage(house: hub.house)
            case .uninstall: UninstallPage(house: hub.house)
            case .updates: UpdatesPage(house: hub.house)
            case .main: EmptyView()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var title: String {
        switch hub.page {
        case .stop: return "Zatrzymaj wszystko"
        case .startup: return "Uruchamiane przy starcie"
        case .clean: return "Porządki"
        case .uninstall: return "Odinstaluj apkę"
        case .updates: return "Aktualizacje apek"
        case .main: return ""
        }
    }
}

private struct Check: View {
    var on: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(on ? Color.white : Color.clear)
            RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(on ? 1 : 0.35), lineWidth: 1.2)
            if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black) }
        }
        .frame(width: 16, height: 16)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: on)
    }
}

private struct BigButton: View {
    var title: String
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 38)
                .background(Color.white.opacity(enabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.97)).disabled(!enabled)
    }
}

private struct StopPage: View {
    @ObservedObject var hub: ControlHub
    @ObservedObject var procs: ProcessControl

    var body: some View {
        let groups: [(StopTarget.Kind, String)] = [(.app, "Otwarte apki"), (.menuApp, "Apki w pasku menu"), (.agent, "Usługi w tle"), (.background, "Procesy w tle")]
        VStack(spacing: 10) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if procs.targets.isEmpty { Text("Szukam…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.top, 20).frame(maxWidth: .infinity) }
                    ForEach(groups, id: \.0) { kind, title in
                        let list = procs.targets.filter { $0.kind == kind }
                        if !list.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionTitle(title)
                                VStack(spacing: 0) {
                                    ForEach(list) { t in
                                        Button { procs.toggle(t.id) } label: {
                                            HStack(spacing: 10) {
                                                Check(on: t.checked)
                                                Image(nsImage: t.bundle.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .unixExecutable)).resizable().frame(width: 20, height: 20)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(t.name).font(.system(size: 12.5)).foregroundStyle(ink).lineLimit(1)
                                                    Text(t.detail).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.middle)
                                                }
                                                Spacer(minLength: 4)
                                                if let item = autostart(t), item.enabled {
                                                    Button { hub.startup.set(item, on: false) } label: {
                                                        Text(hub.startup.busy.contains(item.id) ? "…" : "Wyłącz autostart").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(ink)
                                                            .padding(.horizontal, 8).frame(height: 20).background(cardHi, in: Capsule())
                                                    }
                                                    .buttonStyle(PressStyle()).help("Uruchamia się samo przy logowaniu")
                                                } else if t.memory > 0 { Text(Fmt.bytes(Double(t.memory))).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.5)) }
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                    if !procs.stubborn.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle("Nie chcą się zamknąć")
                            ForEach(procs.stubborn) { t in
                                HStack {
                                    Text(t.name).font(.system(size: 12.5)).foregroundStyle(ink)
                                    Spacer()
                                    Button("Wymuś") { procs.force(t) }.buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.black)
                                        .padding(.horizontal, 10).frame(height: 22).background(Color.white, in: Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            VStack(spacing: 6) {
                if !procs.lastResult.isEmpty { Text(procs.lastResult).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)) }
                let n = procs.targets.filter(\.checked).count
                BigButton(title: procs.stopping ? "Zatrzymuję…" : "Zatrzymaj zaznaczone (\(n))", enabled: n > 0 && !procs.stopping) { procs.stopChecked() }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }
}

extension StopPage {
    func autostart(_ t: StopTarget) -> StartupItem? {
        let items = hub.startup.items
        if let label = t.label { return items.first { $0.label == label && !$0.protected } }
        return items.first { $0.kind == .loginItem && !$0.missing && ($0.name == t.name || ($0.file != nil && $0.file == t.bundle?.path)) }
    }
}

private struct StartupPage: View {
    @ObservedObject var startup: StartupItems

    var body: some View {
        let groups: [(StartupItem.Kind, String)] = [(.userAgent, "Twoje usługi w tle"), (.loginItem, "Apki przy logowaniu"), (.systemAgent, "Agenci innych apek"), (.daemon, "Usługi systemowe (pyta o hasło)")]
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if startup.items.isEmpty { Text("Sprawdzam…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.top, 20).frame(maxWidth: .infinity) }
                if !startup.problem.isEmpty { Text(startup.problem).font(.system(size: 11.5)).foregroundStyle(errorRed) }
                ForEach(groups, id: \.0) { kind, title in
                    let list = startup.items.filter { $0.kind == kind }
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(title)
                            VStack(spacing: 0) {
                                ForEach(list) { item in StartupRow(startup: startup, item: item) }
                            }
                            .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                Button { startup.openSystemSettings() } label: {
                    HStack { Text("Elementy logowania w Ustawieniach").font(.system(size: 12)); Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)) }
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain).padding(.bottom, 14)
            }
            .padding(.horizontal, 14)
        }
    }
}

private struct StartupRow: View {
    @ObservedObject var startup: StartupItems
    var item: StartupItem

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: item.bundle.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .unixExecutable)).resizable().frame(width: 20, height: 20).opacity(item.missing ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.name).font(.system(size: 12.5)).foregroundStyle(ink).lineLimit(1)
                    if item.running { Circle().fill(Color.white).frame(width: 5, height: 5).help("Działa teraz") }
                }
                Text(item.protected ? "Concierge, zawsze włączone" : item.detail).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if startup.busy.contains(item.id) {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 34)
            } else if item.missing {
                Button("Usuń") { startup.remove(item) }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(ink).padding(.horizontal, 9).frame(height: 20).background(card, in: Capsule())
            } else if !item.protected {
                Toggle("", isOn: Binding(get: { item.enabled }, set: { startup.set(item, on: $0) })).toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(.white)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }
}

private struct CleanPage: View {
    @ObservedObject var house: Housekeeping

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.bytes(Double(house.cacheTotal))).font(.system(size: 26, weight: .semibold).monospacedDigit()).foregroundStyle(ink)
                        Text("do wyczyszczenia").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                    Text(lastLine).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                    VStack(spacing: 0) {
                        ForEach(house.caches) { c in
                            HStack {
                                Text(c.name).font(.system(size: 12)).foregroundStyle(ink).lineLimit(1)
                                Spacer()
                                Text(Fmt.bytes(Double(c.size))).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.white.opacity(0.55))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                        }
                        if house.caches.isEmpty { Text(house.scanning ? "Liczę…" : "Nic do sprzątania.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(12) }
                    }
                    .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Cache apek, które teraz działają, i dane Twoich projektów zostają nietknięte. Co tydzień po 6:00 sprząta samo.").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 14)
            }
            VStack(spacing: 6) {
                if !house.message.isEmpty { Text(house.message).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.65)) }
                BigButton(title: house.cleaning ? "Czyszczę…" : "Wyczyść \(Fmt.bytes(Double(house.cacheTotal)))", enabled: !house.cleaning && house.cacheTotal > 0) { house.clean() }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }

    private var lastLine: String {
        guard let d = house.lastRun else { return "Jeszcze nie sprzątane przez Concierge." }
        let f = DateFormatter(); f.locale = Locale(identifier: "pl_PL"); f.dateFormat = "d MMMM, HH:mm"
        return "Ostatnio \(f.string(from: d)), zwolnione \(Fmt.bytes(Double(house.lastFreed)))."
    }
}

private struct UninstallPage: View {
    @ObservedObject var house: Housekeeping
    @State private var query = ""
    @State private var picked: InstalledApp?

    var body: some View {
        if let app = picked { detail(app) } else { list }
    }

    private var list: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                TextField("Szukaj apki", text: $query).textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(ink)
            }
            .padding(.horizontal, 11).frame(height: 30).background(card, in: Capsule())
            .padding(.horizontal, 14)
            if !house.message.isEmpty { Text(house.message).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 14) }
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(house.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { app in
                        Button { picked = app; house.findLeftovers(app) } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 22, height: 22)
                                Text(app.name).font(.system(size: 12.5)).foregroundStyle(ink).lineLimit(1)
                                Spacer()
                                Text(app.size.map { Fmt.bytes(Double($0)) } ?? "…").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
    }

    private func detail(_ app: InstalledApp) -> some View {
        let extra = house.leftovers.filter(\.checked).reduce(Int64(0)) { $0 + $1.size }
        return VStack(spacing: 10) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                            Text("\(app.version.isEmpty ? "" : "wersja \(app.version), ")\(app.size.map { Fmt.bytes(Double($0)) } ?? "")").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Button("Wróć") { picked = nil }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                    }
                    SectionTitle(house.leftovers.isEmpty ? "Resztki: szukam…" : "Resztki w bibliotece (\(house.leftovers.count))")
                    VStack(spacing: 0) {
                        ForEach(house.leftovers) { l in
                            Button { house.toggleLeftover(l.id) } label: {
                                HStack(spacing: 9) {
                                    Check(on: l.checked)
                                    Text(l.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11)).foregroundStyle(ink).lineLimit(1).truncationMode(.head)
                                    Spacer(minLength: 4)
                                    Text(Fmt.bytes(Double(l.size))).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Wszystko trafia do Kosza, więc da się to jeszcze odzyskać.").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 14)
            }
            BigButton(title: "Przenieś do Kosza (\(Fmt.bytes(Double((app.size ?? 0) + extra))))") {
                house.uninstall(app) { ok in if ok { picked = nil } }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }
}

private struct UpdatesPage: View {
    @ObservedObject var house: Housekeeping

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if house.checkingUpdates { Text("Sprawdzam apki…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)) }
                    else if house.updates.isEmpty { Text("Wszystko aktualne.").font(.system(size: 13)).foregroundStyle(ink) }
                    VStack(spacing: 0) {
                        ForEach(house.updates) { u in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: u.app.path)).resizable().frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(u.app.name).font(.system(size: 12.5)).foregroundStyle(ink)
                                    Text("\(u.app.version) → \(u.latest)").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                                Button("Otwórz") { if let l = u.link { NSWorkspace.shared.open(l) } }
                                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 10).frame(height: 22).background(Color.white, in: Capsule())
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                        }
                    }
                    .background(house.updates.isEmpty ? .clear : card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Apki z aktualizatorem Sparkle po otwarciu same proponują nową wersję, apki z App Store otwierają swoją stronę w sklepie.").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 14)
            }
            BigButton(title: house.checkingUpdates ? "Sprawdzam…" : "Sprawdź teraz", enabled: !house.checkingUpdates) { house.checkUpdates(force: true) }
                .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }
}

// MARK: menu bar stats

enum MenuBarStats {
    static func image(_ s: StatsSnapshot) -> NSImage {
        let items: [(String, String)] = [
            ("CPU", "\(Int((s.cpu * 100).rounded()))%" + (s.cpuTemp.map { " \(Int($0.rounded()))°" } ?? "")),
            ("GPU", "\(Int((s.gpu * 100).rounded()))%" + (s.gpuTemp.map { " \(Int($0.rounded()))°" } ?? "")),
            ("RAM", "\(Int((s.memFraction * 100).rounded()))%"),
        ]
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 7.5, weight: .semibold), .foregroundColor: NSColor.black]
        let value: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.black]
        let widths = items.map { max(($0.0 as NSString).size(withAttributes: label).width, ($0.1 as NSString).size(withAttributes: value).width) }
        let gap: CGFloat = 9
        let total = widths.reduce(0, +) + gap * CGFloat(items.count - 1)
        let img = NSImage(size: NSSize(width: ceil(total), height: 22), flipped: false) { _ in
            var x: CGFloat = 0
            for (i, it) in items.enumerated() {
                let w = widths[i]
                let lw = (it.0 as NSString).size(withAttributes: label).width, vw = (it.1 as NSString).size(withAttributes: value).width
                (it.0 as NSString).draw(at: NSPoint(x: x + (w - lw) / 2, y: 12.5), withAttributes: label)
                (it.1 as NSString).draw(at: NSPoint(x: x + (w - vw) / 2, y: -0.5), withAttributes: value)
                x += w + gap
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
