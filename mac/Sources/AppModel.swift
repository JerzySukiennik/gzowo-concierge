// Gzowo Concierge for macOS - observable app state: conversations, selection, host status, and actions that talk to the host.
import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var threads: [ThreadInfo] = []
    @Published var activeID: String = UserDefaults.standard.string(forKey: "activeThread") ?? "main"
    @Published var online = false
    @Published var pending = 0
    @Published var busy = false
    @Published var query = ""
    @Published var shellReady = false
    @Published var hasThreads = false
    @Published var immersive = false
    weak var web: WebHost?
    var requestRename: ((ThreadInfo) -> Void)?
    var requestPoll: (() -> Void)?

    func apply(_ s: HostState) {
        online = s.online; pending = s.pending; busy = s.busy
        if s.online && hasThreads != s.hasThreads { hasThreads = s.hasThreads }
        if s.online && threads != s.threads { threads = s.threads }
    }

    func adoptFromWeb(_ id: String) {
        guard id != activeID else { return }
        activeID = id
        UserDefaults.standard.set(id, forKey: "activeThread")
    }

    func select(_ id: String) {
        activeID = id
        UserDefaults.standard.set(id, forKey: "activeThread")
        web?.call("openThread('\(id)')")
    }

    func newThread() {
        Task {
            if let id = await Api.post("/api/threads")?["id"] as? String {
                requestPoll?()
                try? await Task.sleep(nanoseconds: 250_000_000)
                select(id)
            }
        }
    }

    func rename(_ t: ThreadInfo, to title: String) {
        Task { _ = await Api.post("/api/threads/\(t.id)/rename", ["title": title]); requestPoll?() }
    }

    func delete(_ t: ThreadInfo) {
        Task {
            _ = await Api.send("DELETE", "/api/threads/\(t.id)")
            if t.id == activeID { select(threads.first(where: { $0.id != t.id })?.id ?? "main") }
            requestPoll?()
        }
    }

    func openView(_ name: String) { web?.call("openView('\(name)')") }

    func probeShell() {
        for delay in [1.0, 2.5, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.web?.view.evaluateJavaScript("typeof window.conciergeShell === 'object' && typeof window.conciergeShell.openView === 'function'") { result, _ in
                    if let ok = result as? Bool, ok { Task { @MainActor in self?.shellReady = true } }
                }
            }
        }
    }

    var filtered: [ThreadInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? threads : threads.filter { $0.title.lowercased().contains(q) }
    }

    struct Group: Identifiable { var id: String; var items: [ThreadInfo] }
    var groups: [Group] {
        let cal = Calendar.current
        var today: [ThreadInfo] = [], yesterday: [ThreadInfo] = [], older: [ThreadInfo] = []
        for t in filtered {
            let d = Date(timeIntervalSince1970: t.updated / 1000)
            if cal.isDateInToday(d) { today.append(t) } else if cal.isDateInYesterday(d) { yesterday.append(t) } else { older.append(t) }
        }
        return [Group(id: "Dzisiaj", items: today), Group(id: "Wczoraj", items: yesterday), Group(id: "Wcześniej", items: older)].filter { !$0.items.isEmpty }
    }
}

enum Api {
    static func send(_ method: String, _ path: String, _ body: [String: Any]? = nil) async -> [String: Any]? {
        guard let url = URL(string: Config.base + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 6
        if let body { req.setValue("application/json", forHTTPHeaderField: "content-type"); req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func post(_ path: String, _ body: [String: Any]? = nil) async -> [String: Any]? { await send("POST", path, body) }
}
