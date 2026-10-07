// Gzowo Concierge for macOS - the main window: Liquid Glass backdrop, native sidebar, transparent web content card, drag strips, offline overlay.
import AppKit
import SwiftUI

final class DragStrip: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) } else { super.mouseDown(with: event) }
    }
}

final class OfflineModel: ObservableObject {
    @Published var visible = false
    var retry: () -> Void = {}
}

struct OfflineOverlay: View {
    @ObservedObject var model: OfflineModel

    var body: some View {
        if model.visible {
            VStack(spacing: 14) {
                Image(systemName: "moon.zzz").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                Text("Host nie odpowiada").font(.system(size: 20, weight: .semibold))
                Text("Concierge czeka na usługę w tle. Spróbuję połączyć się ponownie za chwilę.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
                Button("Spróbuj teraz") { model.retry() }.buttonStyle(.glass).controlSize(.large)
            }
            .padding(34)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var offline: OfflineModel
    let web: WebHost

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 28, style: .continuous)
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: Config.sidebarWidth)
            ZStack {
                WebViewHost(web: web)
                    .background(Color.clear.glassEffect(.regular, in: card))
                    .clipShape(card)
                    .overlay(card.strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
                OfflineOverlay(model: offline)
            }
            .padding(.trailing, Config.inset)
            .padding(.vertical, Config.inset)
        }
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate {
    let web = WebHost()
    let offline = OfflineModel()

    init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Config.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Concierge"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.minSize = Config.minSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.setFrameAutosaveName("ConciergeMain2")
        super.init(window: window)
        window.delegate = self
        model.web = web

        let root = NSView(frame: NSRect(origin: .zero, size: Config.defaultSize))
        root.wantsLayer = true
        root.autoresizingMask = [.width, .height]

        let glass = NSGlassEffectView(frame: root.bounds)
        glass.style = .regular
        glass.cornerRadius = 0
        glass.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: RootView(model: model, offline: offline, web: web))
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.contentView = hosting
        root.addSubview(glass)

        let left = DragStrip(frame: NSRect(x: 0, y: root.bounds.height - 38, width: Config.sidebarWidth, height: 38))
        left.autoresizingMask = [.minYMargin]
        root.addSubview(left)
        let right = DragStrip(frame: NSRect(x: Config.sidebarWidth, y: root.bounds.height - Config.inset, width: root.bounds.width - Config.sidebarWidth, height: Config.inset))
        right.autoresizingMask = [.width, .minYMargin]
        root.addSubview(right)

        window.contentView = root
        if !window.setFrameUsingName("ConciergeMain2") { window.center() }

        offline.retry = { [weak self] in self?.web.reload() }
        web.onLoadStateChange = { [weak self, weak model] ok in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) { self?.offline.visible = !ok }
                if ok, let id = model?.activeID {
                    for delay in [0.4, 1.6] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.web.call("openThread('\(id)')") } }
                }
            }
        }
        web.load()
    }

    required init?(coder: NSCoder) { fatalError() }

    var isShown: Bool { window?.isVisible == true && NSApp.isActive }

    func show() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        web.call("closeLive()")
        window?.orderOut(nil)
    }

    func toggle() { isShown ? hide() : show() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
