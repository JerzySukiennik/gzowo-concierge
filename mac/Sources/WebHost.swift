// Gzowo Concierge for macOS - transparent WKWebView that hosts the Concierge UI and bridges messages with the native shell.
import AppKit
import WebKit

final class WebHost: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let view: WKWebView
    var onMessage: (([String: Any]) -> Void)?
    var onLoadStateChange: ((Bool) -> Void)?
    private var retryTimer: Timer?

    override init() {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "ConciergeMac/1.0"
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        let script = WKUserScript(source: """
            document.documentElement.dataset.shell = 'mac';
            document.documentElement.dataset.sidebar = 'native';
            document.documentElement.style.setProperty('--shell-top', '0px');
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(WeakHandler(self), name: "concierge")
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsMagnification = false
        view.isInspectable = true
        view.autoresizingMask = [.width, .height]
    }

    func load() {
        view.load(URLRequest(url: Config.host, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func reload() { load() }

    func call(_ expression: String) {
        view.evaluateJavaScript("window.conciergeShell && window.conciergeShell.\(expression)", completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { onMessage?(body) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        retryTimer?.invalidate(); retryTimer = nil
        onLoadStateChange?(true)
        if let js = ProcessInfo.processInfo.environment["CONCIERGE_EVAL"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.view.evaluateJavaScript(js) { result, error in
                    let text = error.map { "ERR \($0)" } ?? "\(result ?? "nil")"
                    try? text.write(toFile: "/tmp/concierge-eval.txt", atomically: true, encoding: .utf8)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed() }

    private func failed() {
        onLoadStateChange?(false)
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.load() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, action.navigationType == .linkActivated, !Config.localHosts.contains(url.host ?? "") {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(Config.localHosts.contains(origin.host) ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }
}

private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
