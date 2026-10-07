// Gzowo Concierge for macOS - SwiftUI wrapper that places the shared transparent WKWebView inside the layout.
import SwiftUI
import WebKit

struct WebViewHost: NSViewRepresentable {
    let web: WebHost
    func makeNSView(context: Context) -> WKWebView { web.view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
