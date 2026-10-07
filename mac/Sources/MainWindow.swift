// Gzowo Concierge for macOS - the main window: opaque (smooth on Intel), in-window backdrop, glass sidebar and content card, drag strips, offline overlay.
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
                Button("Spróbuj teraz") { model.retry() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(34)
            .glassPanel(radius: 30, strength: .regularMaterial)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var offline: OfflineModel
    let web: WebHost

    var body: some View {
        let on = model.immersive
        ZStack {
            Backdrop()
            HStack(spacing: on ? 0 : Config.inset) {
                if !on {
                    SidebarView(model: model)
                        .frame(width: Config.sidebarWidth)
                        .glassPanel(radius: 28, strength: .regularMaterial)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ZStack {
                    WebViewHost(web: web)
                        .modifier(CardChrome(immersive: on))
                    OfflineOverlay(model: offline)
                }
            }
            .padding(on ? 0 : Config.inset)
        }
        .animation(.easeInOut(duration: 0.26), value: on)
    }
}

struct CardChrome: ViewModifier {
    var immersive: Bool
    func body(content: Content) -> some View {
        if immersive {
            content.background(Color(nsColor: .windowBackgroundColor))
        } else {
            content.glassPanel(radius: 28, strength: .thinMaterial)
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
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.minSize = Config.minSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.setFrameAutosaveName("ConciergeMain3")
        super.init(window: window)
        window.delegate = self
        model.web = web

        let root = NSView(frame: NSRect(origin: .zero, size: Config.defaultSize))
        root.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: RootView(model: model, offline: offline, web: web))
        hosting.frame = root.bounds
        hosting.autoresizingMask = [.width, .height]
        root.addSubview(hosting)

        let left = DragStrip(frame: NSRect(x: 0, y: root.bounds.height - 40, width: Config.sidebarWidth + Config.inset, height: 40))
        left.autoresizingMask = [.minYMargin]
        root.addSubview(left)
        let right = DragStrip(frame: NSRect(x: Config.sidebarWidth + Config.inset, y: root.bounds.height - Config.inset, width: root.bounds.width - Config.sidebarWidth - Config.inset, height: Config.inset))
        right.autoresizingMask = [.width, .minYMargin]
        root.addSubview(right)

        window.contentView = root
        if !window.setFrameUsingName("ConciergeMain3") { window.center() }

        offline.retry = { [weak self] in self?.web.reload() }
        web.onLoadStateChange = { [weak self, weak model] ok in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) { self?.offline.visible = !ok }
                if ok { model?.shellReady = false; model?.probeShell() }
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
