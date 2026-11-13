// Gzowo Concierge for macOS - housekeeping: weekly cache cleaning, uninstalling apps together with their leftovers (to the Trash), and checking apps for updates.
import AppKit

struct CacheEntry: Identifiable, Equatable {
    var id: String { path }
    var name: String
    var path: String
    var size: Int64
}

struct InstalledApp: Identifiable, Equatable {
    var id: String { path }
    var name: String
    var path: String
    var bundleID: String
    var version: String
    var build: String
    var size: Int64?
}

struct Leftover: Identifiable, Equatable {
    var id: String { path }
    var path: String
    var size: Int64
    var checked = true
}

struct AppUpdate: Identifiable, Equatable {
    var id: String { app.path }
    var app: InstalledApp
    var latest: String
    var link: URL?
}

enum FileSize {
    static func of(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { return Int64(v.totalFileAllocatedSize ?? 0) }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { total += Int64(v.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}

@MainActor
final class Housekeeping: ObservableObject {
    @Published private(set) var caches: [CacheEntry] = []
    @Published private(set) var scanning = false
    @Published private(set) var cleaning = false
    @Published private(set) var lastFreed: Int64 = UserDefaults.standard.object(forKey: "cleanerLastFreed") as? Int64 ?? 0
    @Published private(set) var lastRun: Date? = UserDefaults.standard.object(forKey: "cleanerLastRun") as? Date
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var leftovers: [Leftover] = []
    @Published private(set) var updates: [AppUpdate] = []
    @Published private(set) var checkingUpdates = false
    @Published private(set) var updatesChecked: Date? = UserDefaults.standard.object(forKey: "updatesChecked") as? Date
    @Published var message = ""
    private var weekly: Timer?
    private var checkedNow = false

    var cacheTotal: Int64 { caches.reduce(0) { $0 + $1.size } }

    private nonisolated static let keepCaches: [String] = ["com.apple.", "ms-playwright", "fun.gzowo", "gzowo", "claude", "com.anthropic", "CloudKit", "GeoServices", "familycircled", "FamilyCircle", "org.swift.swiftpm", "JetBrains"]

    func startSchedule() {
        weekly?.invalidate()
        weekly = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in Task { @MainActor in self?.autoClean() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.autoClean() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in try? await Task.sleep(for: .seconds(120)); self?.autoClean() }
        }
    }

    private func autoClean() {
        guard let lastRun else {
            self.lastRun = Date()
            UserDefaults.standard.set(Date(), forKey: "cleanerLastRun")
            return
        }
        let due = Date().timeIntervalSince(lastRun) > 7 * 86400
        guard due, Calendar.current.component(.hour, from: Date()) >= 6, !cleaning else { return }
        scanCaches { [weak self] in self?.clean() }
    }

    func scanCaches(then: (() -> Void)? = nil) {
        guard !scanning else { return }
        scanning = true
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() } + NSWorkspace.shared.runningApplications.compactMap { $0.localizedName?.lowercased() })
        Task.detached(priority: .utility) {
            let home = NSHomeDirectory()
            var out: [CacheEntry] = []
            let root = home + "/Library/Caches"
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] {
                let low = name.lowercased()
                if Self.keepCaches.contains(where: { low.hasPrefix($0.lowercased()) }) || running.contains(low) || running.contains(where: { !$0.isEmpty && low.hasPrefix($0 + ".") }) { continue }
                let path = root + "/" + name
                let size = FileSize.of(path)
                if size > 512 * 1024 { out.append(CacheEntry(name: name, path: path, size: size)) }
            }
            for (name, path) in [("Xcode DerivedData", home + "/Library/Developer/Xcode/DerivedData"), ("Symulatory iOS, cache", home + "/Library/Developer/CoreSimulator/Caches")] {
                let size = FileSize.of(path)
                if size > 1024 * 1024 { out.append(CacheEntry(name: name, path: path, size: size)) }
            }
            let logs = home + "/Library/Logs"
            var oldLogs: Int64 = 0
            if let e = FileManager.default.enumerator(at: URL(fileURLWithPath: logs), includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .totalFileAllocatedSizeKey]) {
                for case let f as URL in e {
                    guard let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .totalFileAllocatedSizeKey]), v.isRegularFile == true,
                          let d = v.contentModificationDate, Date().timeIntervalSince(d) > 7 * 86400 else { continue }
                    oldLogs += Int64(v.totalFileAllocatedSize ?? 0)
                }
            }
            if oldLogs > 0 { out.append(CacheEntry(name: "Stare logi (ponad tydzień)", path: logs + "#old", size: oldLogs)) }
            out.sort { $0.size > $1.size }
            let result = out
            await MainActor.run {
                self.caches = result
                self.scanning = false
                then?()
            }
        }
    }

    func clean() {
        guard !cleaning, !caches.isEmpty else { return }
        cleaning = true
        let list = caches
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            var freed: Int64 = 0
            for c in list {
                if c.path.hasSuffix("#old") {
                    let logs = String(c.path.dropLast(4))
                    if let e = fm.enumerator(at: URL(fileURLWithPath: logs), includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) {
                        for case let f as URL in e {
                            guard let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), v.isRegularFile == true,
                                  let d = v.contentModificationDate, Date().timeIntervalSince(d) > 7 * 86400 else { continue }
                            try? fm.removeItem(at: f)
                        }
                    }
                    freed += c.size
                    continue
                }
                guard let items = try? fm.contentsOfDirectory(atPath: c.path) else { continue }
                for i in items { try? fm.removeItem(atPath: c.path + "/" + i) }
                freed += max(0, c.size - FileSize.of(c.path))
            }
            let total = freed
            await MainActor.run {
                self.cleaning = false
                self.lastFreed = total
                self.lastRun = Date()
                UserDefaults.standard.set(total, forKey: "cleanerLastFreed")
                UserDefaults.standard.set(Date(), forKey: "cleanerLastRun")
                self.message = "Zwolnione: \(Fmt.bytes(Double(total)))"
                self.scanCaches()
            }
        }
    }

    // MARK: apps

    func loadApps() {
        Task.detached(priority: .userInitiated) {
            let list = Self.installedApps()
            await MainActor.run { self.apps = list }
            for app in list {
                let size = FileSize.of(app.path)
                await MainActor.run {
                    if let i = self.apps.firstIndex(where: { $0.path == app.path }) { self.apps[i].size = size }
                }
            }
        }
    }

    nonisolated static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var paths: [String] = []
        for root in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
                let p = root + "/" + name
                if name.hasSuffix(".app") { paths.append(p) }
                else if name != "Utilities", !name.hasSuffix(".localized"), let inner = try? fm.contentsOfDirectory(atPath: p) {
                    paths += inner.filter { $0.hasSuffix(".app") }.map { p + "/" + $0 }
                }
            }
        }
        let mine = Bundle.main.bundleIdentifier
        return paths.compactMap { p in
            guard let b = Bundle(path: p), let bid = b.bundleIdentifier, !bid.hasPrefix("com.apple."), bid != mine else { return nil }
            let info = b.infoDictionary ?? [:]
            let name = fm.displayName(atPath: p).replacingOccurrences(of: ".app", with: "")
            return InstalledApp(name: name, path: p, bundleID: bid, version: info["CFBundleShortVersionString"] as? String ?? "", build: info["CFBundleVersion"] as? String ?? "")
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func findLeftovers(_ app: InstalledApp) {
        leftovers = []
        Task.detached(priority: .userInitiated) {
            let found = Self.leftovers(for: app)
            await MainActor.run { self.leftovers = found }
        }
    }

    nonisolated static func leftovers(for app: InstalledApp) -> [Leftover] {
        let fm = FileManager.default
        let lib = NSHomeDirectory() + "/Library"
        let bid = app.bundleID.lowercased()
        let name = app.name.lowercased()
        let compact = name.replacingOccurrences(of: " ", with: "")
        func matches(_ entry: String) -> Bool {
            let e = entry.lowercased()
            if e.hasPrefix(bid) { return true }
            if e.contains("." + bid) && e.count < bid.count + 20 { return true }
            let stem = (e as NSString).deletingPathExtension
            return name.count >= 4 && (stem == name || stem == compact)
        }
        var out: [Leftover] = []
        for dir in ["Application Support", "Caches", "Preferences", "Containers", "Group Containers", "Saved Application State", "Logs", "HTTPStorages", "WebKit", "Application Scripts", "Cookies", "LaunchAgents"] {
            let root = lib + "/" + dir
            for entry in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where matches(entry) {
                let p = root + "/" + entry
                out.append(Leftover(path: p, size: FileSize.of(p)))
            }
        }
        if let agents = try? fm.contentsOfDirectory(atPath: lib + "/LaunchAgents") {
            for a in agents where !out.contains(where: { $0.path.hasSuffix("/" + a) }) {
                let p = lib + "/LaunchAgents/" + a
                if let s = try? String(contentsOfFile: p, encoding: .utf8), s.contains(app.path) { out.append(Leftover(path: p, size: FileSize.of(p))) }
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    func toggleLeftover(_ id: String) {
        if let i = leftovers.firstIndex(where: { $0.id == id }) { leftovers[i].checked.toggle() }
    }

    func uninstall(_ app: InstalledApp, done: @escaping (Bool) -> Void) {
        let urls = [URL(fileURLWithPath: app.path)] + leftovers.filter(\.checked).map { URL(fileURLWithPath: $0.path) }
        let uid = getuid()
        for a in leftovers.filter(\.checked) where a.path.contains("/LaunchAgents/") {
            if let d = FileManager.default.contents(atPath: a.path), let pl = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any], let label = pl["Label"] as? String {
                PowerControl.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
            }
        }
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == app.bundleID }.forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NSWorkspace.shared.recycle(urls) { moved, error in
                Task { @MainActor in
                    let ok = error == nil || !moved.isEmpty
                    self.message = ok ? "\(app.name) jest w koszu (razem z resztkami: \(moved.count - 1))." : "Nie udało się usunąć \(app.name)."
                    if ok { self.apps.removeAll { $0.path == app.path }; self.updates.removeAll { $0.app.path == app.path } }
                    self.leftovers = []
                    done(ok)
                }
            }
        }
    }

    // MARK: updates

    func checkUpdates(force: Bool = false) {
        guard !checkingUpdates else { return }
        if !force, checkedNow, let last = updatesChecked, Date().timeIntervalSince(last) < 6 * 3600 { return }
        checkedNow = true
        checkingUpdates = true
        Task.detached(priority: .utility) {
            let apps = Self.installedApps()
            var found: [AppUpdate] = []
            await withTaskGroup(of: AppUpdate?.self) { group in
                for app in apps { group.addTask { await Self.update(for: app) } }
                for await u in group { if let u { found.append(u) } }
            }
            found.sort { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
            let result = found
            await MainActor.run {
                self.updates = result
                self.checkingUpdates = false
                self.updatesChecked = Date()
                UserDefaults.standard.set(Date(), forKey: "updatesChecked")
            }
        }
    }

    nonisolated static func newer(_ a: String, than b: String) -> Bool {
        let pa = a.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }, pb = b.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard !pa.isEmpty, !pb.isEmpty else { return false }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func update(for app: InstalledApp) async -> AppUpdate? {
        let info = Bundle(path: app.path)?.infoDictionary ?? [:]
        let session = URLSession(configuration: { let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 12; return c }())
        if let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)) {
            guard let (data, _) = try? await session.data(from: feed) else { return nil }
            let parser = AppcastParser(data: data)
            guard let best = parser.items.max(by: { newer($1.short.isEmpty ? $1.build : $1.short, than: $0.short.isEmpty ? $0.build : $0.short) }) else { return nil }
            let theirs = best.short.isEmpty ? best.build : best.short
            if !best.short.isEmpty && !app.version.isEmpty ? newer(best.short, than: app.version) : newer(best.build, than: app.build) {
                return AppUpdate(app: app, latest: theirs, link: URL(fileURLWithPath: app.path))
            }
            return nil
        }
        if FileManager.default.fileExists(atPath: app.path + "/Contents/_MASReceipt/receipt"),
           let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(app.bundleID)&entity=macSoftware"),
           let (data, _) = try? await session.data(from: url),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let r = (j["results"] as? [[String: Any]])?.first,
           let v = r["version"] as? String, newer(v, than: app.version) {
            return AppUpdate(app: app, latest: v, link: (r["trackViewUrl"] as? String).flatMap { URL(string: $0.replacingOccurrences(of: "https://", with: "macappstore://")) })
        }
        return nil
    }
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    struct Item { var short = ""; var build = "" }
    private(set) var items: [Item] = []
    private var current: Item?
    private var text = ""
    private var element = ""

    init(data: Data) {
        super.init()
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        element = name
        text = ""
        if name == "item" { current = Item() }
        if name == "enclosure", current != nil {
            if let s = attributes["sparkle:shortVersionString"], current?.short.isEmpty == true { current?.short = s }
            if let b = attributes["sparkle:version"], current?.build.isEmpty == true { current?.build = b }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "sparkle:shortVersionString", !t.isEmpty { current?.short = t }
        if name == "sparkle:version", !t.isEmpty { current?.build = t }
        if name == "item", let c = current { items.append(c); current = nil }
        text = ""
    }
}
