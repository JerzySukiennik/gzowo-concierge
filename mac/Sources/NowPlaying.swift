// Gzowo Concierge for macOS - now playing: runs the MediaRemote bridge under /usr/bin/perl and publishes title, progress, artwork and controls for the island.
import AppKit
import Combine

struct NowPlaying: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var bundle = ""
    var app = ""
    var playing = false
    var duration: Double = 0
    var elapsed: Double = 0
    var rate: Double = 1
    var stamp = Date.distantPast
    var artId = ""

    var isEmpty: Bool { title.isEmpty }

    func position(at now: Date) -> Double {
        let p = elapsed + (playing ? now.timeIntervalSince(stamp) * max(rate, 0) : 0)
        return duration > 0 ? max(0, min(duration, p)) : max(0, p)
    }

    var subtitle: String {
        let parts = [artist, album].filter { !$0.isEmpty && $0 != title }
        return parts.first ?? app
    }
}

@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var info = NowPlaying()
    @Published private(set) var art: NSImage?
    @Published private(set) var appIcon: NSImage?
    var onChange: (_ trackChanged: Bool, _ playChanged: Bool) -> Void = { _, _ in }
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var failures = 0
    private var names: [String: (String, NSImage?)] = [:]
    private let enabledKey = "mediaOnIsland"

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey); newValue ? start() : stop() }
    }

    private var bridge: String? {
        let p = Bundle.main.resourceURL?.appendingPathComponent("libnowplaying.dylib").path
        return p.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    func start() {
        guard enabled, process == nil, let bridge, FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", "use DynaLoader; my $l = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error(); DynaLoader::dl_install_xsub('main::run', DynaLoader::dl_find_symbol($l, 'np_run')); run();", bridge]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { h.readabilityHandler = nil; return }
            Task { @MainActor in self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] _ in Task { @MainActor in self?.ended() } }
        do { try p.run() } catch { return }
        process = p
        input = inp.fileHandleForWriting
    }

    func stop() {
        let p = process
        process = nil
        try? input?.close()
        input = nil
        p?.terminate()
        info = NowPlaying(); art = nil; appIcon = nil
    }

    private func ended() {
        guard process != nil else { return }
        process = nil; input = nil
        failures += 1
        info = NowPlaying(); art = nil
        guard failures < 8 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(min(60, failures * failures * 2))) { [weak self] in self?.start() }
    }

    func send(_ command: String) {
        guard let input else { return }
        try? input.write(contentsOf: Data((command + "\n").utf8))
        if command == "toggle" { info.elapsed = info.position(at: Date()); info.stamp = Date(); info.playing.toggle() }
    }

    func seek(to seconds: Double) {
        send("seek \(max(0, seconds))")
        info.elapsed = max(0, seconds); info.stamp = Date()
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { apply(obj) }
        }
    }

    private func apply(_ o: [String: Any]) {
        guard o["type"] as? String == "np" else { if o["type"] as? String == "ready" { failures = 0 }; return }
        if o["empty"] as? Bool == true {
            if !info.isEmpty { info = NowPlaying(); art = nil; appIcon = nil; onChange(true, true) }
            return
        }
        var n = NowPlaying()
        let (title, source) = Self.tidy(o["title"] as? String ?? "")
        n.title = title
        n.artist = o["artist"] as? String ?? ""
        n.album = o["album"] as? String ?? ""
        n.bundle = o["bundle"] as? String ?? ""
        n.playing = (o["playing"] as? Bool) ?? ((o["playing"] as? Int ?? 0) != 0)
        n.duration = o["duration"] as? Double ?? 0
        n.elapsed = o["elapsed"] as? Double ?? 0
        n.rate = (o["rate"] as? Double).map { $0 > 0 ? $0 : 1 } ?? 1
        n.stamp = Date(timeIntervalSince1970: o["ts"] as? Double ?? Date().timeIntervalSince1970)
        n.artId = o["artId"] as? String ?? ""
        let (name, icon) = appInfo(n.bundle, fallback: o["client"] as? String ?? "")
        n.app = source ?? name
        if let b64 = o["art"] as? String, let d = Data(base64Encoded: b64), let img = NSImage(data: d) { art = img }
        else if n.artId.isEmpty { art = nil }
        appIcon = icon
        let trackChanged = n.title != info.title || n.artist != info.artist
        let playChanged = n.playing != info.playing
        info = n
        if trackChanged || playChanged { onChange(trackChanged, playChanged) }
    }

    private static func tidy(_ t: String) -> (String, String?) {
        let s = t.trimmingCharacters(in: .whitespaces)
        for source in ["Prime Video", "YouTube", "Netflix", "Disney+", "Max"] where s.hasPrefix(source + ": ") { return (String(s.dropFirst(source.count + 2)), source) }
        if s.hasSuffix(" - YouTube") { return (String(s.dropLast(10)), "YouTube") }
        return (s, nil)
    }

    private func appInfo(_ bundle: String, fallback: String) -> (String, NSImage?) {
        if let hit = names[bundle] { return hit }
        var result = (fallback, NSImage?.none)
        if !bundle.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            result = (name.isEmpty ? fallback : name, NSWorkspace.shared.icon(forFile: url.path))
        }
        names[bundle] = result
        return result
    }
}
