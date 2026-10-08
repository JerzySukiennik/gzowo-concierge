// Gzowo Concierge for macOS - polls the local host for online, busy, pending approvals and the conversation list.
import Foundation

struct ThreadInfo: Equatable, Identifiable {
    var id: String
    var title: String
    var updated: Double
    var busy: Bool
}

struct PendingItem: Equatable, Identifiable {
    var id: String
    var summary: String
}

struct HostState: Equatable {
    var online = false
    var busy = false
    var pending = 0
    var live = "idle"
    var threads: [ThreadInfo] = []
    var hasThreads = false
    var pendingItems: [PendingItem] = []
    var avatarShape = "circle"
    var avatarColor = "auto"
    var briefTs = 0.0
    var briefText = ""
    var briefThread = "poranny-brief"
}

final class HostMonitor {
    var onChange: ((HostState) -> Void)?
    private(set) var state = HostState()
    private var timer: Timer?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 2
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.poll() }
    }

    func pollNow() { poll() }

    func setLive(_ live: String) {
        guard state.live != live else { return }
        state.live = live
        onChange?(state)
    }

    private func poll() {
        session.dataTask(with: URL(string: "\(Config.base)/api/state")!) { [weak self] data, response, _ in
            var next = self?.state ?? HostState()
            next.online = false
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                next.online = true
                next.busy = json["busy"] as? Bool ?? false
                let pend = (json["pending"] as? [[String: Any]] ?? []).compactMap { p -> PendingItem? in
                    guard let id = p["id"] as? String else { return nil }
                    return PendingItem(id: id, summary: p["summary"] as? String ?? "")
                }
                next.pendingItems = pend
                next.pending = pend.count
                if let av = json["avatar"] as? [String: Any] {
                    next.avatarShape = av["shape"] as? String ?? "circle"
                    next.avatarColor = av["color"] as? String ?? "auto"
                }
                if let b = json["brief"] as? [String: Any] {
                    next.briefThread = b["thread"] as? String ?? "poranny-brief"
                    if let last = b["last"] as? [String: Any] {
                        next.briefTs = last["ts"] as? Double ?? 0
                        next.briefText = last["text"] as? String ?? ""
                    }
                }
                next.hasThreads = json["threads"] != nil
                next.threads = (json["threads"] as? [[String: Any]] ?? []).compactMap { t in
                    guard let id = t["id"] as? String else { return nil }
                    return ThreadInfo(id: id, title: t["title"] as? String ?? "Rozmowa", updated: (t["updated"] as? Double) ?? 0, busy: t["busy"] as? Bool ?? false)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if next != self.state { self.state = next; self.onChange?(next) }
            }
        }.resume()
    }
}
