// Gzowo Concierge for macOS - per-app volume: apps playing sound get their own slider; below 100% the app's audio is tapped (Core Audio process tap) and played back quieter.
import AppKit
import AudioToolbox
import CoreAudio

struct MixerApp: Identifiable, Equatable {
    var id: String
    var name: String
    var bundle: URL?
    var processes: [AudioObjectID]
    var playing: Bool
    var volume: Float
}

private final class GainBox: @unchecked Sendable {
    var gain: Float = 1
    var frames = 0
    var inPeak: Float = 0
    var outPeak: Float = 0
}

private final class AppTap {
    let processes: [AudioObjectID]
    let output: String
    let box = GainBox()
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var procID: AudioDeviceIOProcID?

    init?(processes: [AudioObjectID], outputUID: String, gain: Float) {
        self.processes = processes
        self.output = outputUID
        box.gain = gain
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.muteBehavior = .muted
        desc.isPrivate = true
        desc.name = "Concierge mikser"
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr, tapID != 0 else { return nil }
        let tapUID = desc.uuid.uuidString
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Concierge mikser",
            kAudioAggregateDeviceUIDKey: "fun.gzowo.concierge.mixer." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggregateID) == noErr, aggregateID != 0 else { destroy(); return nil }
        let box = self.box
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            Self.render(input, output, gain: box.gain)
            box.frames += 1
            if let d = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).first?.mData { box.inPeak = max(box.inPeak, abs(d.assumingMemoryBound(to: Float.self)[0])) }
            if let d = UnsafeMutableAudioBufferListPointer(output).first?.mData { box.outPeak = max(box.outPeak, abs(d.assumingMemoryBound(to: Float.self)[0])) }
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else { destroy(); return nil }
    }

    private static func render(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        var index = 0
        for b in outs {
            guard let d = b.mData else { continue }
            let p = d.assumingMemoryBound(to: Float.self)
            let ch = Int(max(1, b.mNumberChannels)), frames = Int(b.mDataByteSize) / 4 / ch
            for c in 0..<ch {
                defer { index += 1 }
                var src: UnsafeMutablePointer<Float>?
                var stride = 1, offset = 0, avail = 0
                if ins.count == 1, let sd = ins[0].mData {
                    let ic = Int(max(1, ins[0].mNumberChannels))
                    src = sd.assumingMemoryBound(to: Float.self); stride = ic; offset = index % ic; avail = Int(ins[0].mDataByteSize) / 4 / ic
                } else if ins.count > 1, let sd = ins[index % ins.count].mData {
                    let buf = ins[index % ins.count], ic = Int(max(1, buf.mNumberChannels))
                    src = sd.assumingMemoryBound(to: Float.self); stride = ic; offset = 0; avail = Int(buf.mDataByteSize) / 4 / ic
                }
                let n = min(frames, avail)
                if let src { for f in 0..<n { p[f * ch + c] = src[f * stride + offset] * gain } }
                for f in (src == nil ? 0 : n)..<frames { p[f * ch + c] = 0 }
            }
        }
    }

    func destroy() {
        if let procID, aggregateID != 0 { AudioDeviceStop(aggregateID, procID); AudioDeviceDestroyIOProcID(aggregateID, procID) }
        procID = nil
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = 0 }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID); tapID = 0 }
    }

    deinit { destroy() }
}

@MainActor
final class AppMixer: ObservableObject {
    @Published private(set) var apps: [MixerApp] = []
    @Published private(set) var master: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var problem = ""
    private var taps: [String: AppTap] = [:]
    private var saved: [String: Float] = (UserDefaults.standard.dictionary(forKey: "mixerVolumes") as? [String: Float]) ?? [:]
    private var listening = false
    private var watch: Timer?

    func start() {
        guard !listening else { return }
        listening = true
        for sel in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice] {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in
                Task { @MainActor in self?.refresh(rebuild: sel == kAudioHardwarePropertyDefaultOutputDevice) }
            }
        }
        refresh()
        if saved.values.contains(where: { $0 < 0.999 }) { startWatch() }
    }

    func setPanelOpen(_ open: Bool) {
        if open { refresh(); startWatch() } else if !saved.values.contains(where: { $0 < 0.999 }) { watch?.invalidate(); watch = nil }
    }

    private func startWatch() {
        guard watch == nil else { return }
        watch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    func stopAll() { taps.values.forEach { $0.destroy() }; taps = [:] }

    func debugLine() -> String {
        taps.map { id, t in
            let line = "\(URL(fileURLWithPath: id).lastPathComponent) gain=\(t.box.gain) callbacks=\(t.box.frames) inPeak=\(t.box.inPeak) outPeak=\(t.box.outPeak) procs=\(t.processes.count)"
            t.box.inPeak = 0; t.box.outPeak = 0
            return line
        }.joined(separator: " | ") + " apps=" + apps.map { "\($0.name):\($0.playing ? "gra" : "cisza"):\($0.volume)" }.joined(separator: ",") + " problem=" + problem
    }

    func setVolume(_ app: MixerApp, _ v: Float) {
        let value = max(0, min(1, v))
        saved[app.id] = value >= 0.995 ? nil : value
        UserDefaults.standard.set(saved, forKey: "mixerVolumes")
        if let i = apps.firstIndex(where: { $0.id == app.id }) { apps[i].volume = value }
        if let tap = taps[app.id] {
            if value >= 0.995 { tap.destroy(); taps[app.id] = nil } else { tap.box.gain = value }
        } else if value < 0.995 {
            apply(apps.first { $0.id == app.id } ?? app, output: Self.outputUID())
            startWatch()
        }
    }

    func setMaster(_ v: Float) {
        Self.setMainVolume(v)
        master = Self.mainVolume()
        if v > 0.001 && muted { Self.setMute(false); muted = false }
    }

    func toggleMute() {
        Self.setMute(!muted)
        muted = Self.isMuted()
    }

    func refresh(rebuild: Bool = false) {
        master = Self.mainVolume()
        muted = Self.isMuted()
        let output = Self.outputUID()
        var groups: [String: MixerApp] = [:]
        let me = ProcessInfo.processInfo.processIdentifier
        for obj in Self.processObjects() {
            let pid = Self.pid(of: obj)
            guard pid > 0, pid != me else { continue }
            let path = ProcessInfoReader.path(pid)
            guard !path.isEmpty, !path.hasPrefix("/System/"), !path.hasPrefix("/usr/") else { continue }
            let bundle = ProcessControl.appBundle(path)
            let key = bundle?.path ?? path
            let name = bundle.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? URL(fileURLWithPath: path).lastPathComponent
            var g = groups[key] ?? MixerApp(id: key, name: name, bundle: bundle, processes: [], playing: false, volume: saved[key] ?? 1)
            g.processes.append(obj)
            if Self.isRunningOutput(obj) { g.playing = true }
            groups[key] = g
        }
        let list = groups.values.filter { $0.playing || $0.volume < 0.995 }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if list != apps { apps = list }
        for (id, tap) in taps {
            guard let app = groups[id], app.volume < 0.995 else { tap.destroy(); taps[id] = nil; continue }
            if rebuild || Set(tap.processes) != Set(app.processes) || tap.output != output { tap.destroy(); taps[id] = nil }
        }
        for app in groups.values where app.volume < 0.995 && taps[app.id] == nil { apply(app, output: output) }
    }

    private func apply(_ app: MixerApp, output: String) {
        guard !output.isEmpty, !app.processes.isEmpty else { return }
        if let tap = AppTap(processes: app.processes, outputUID: output, gain: app.volume) {
            taps[app.id] = tap
            problem = ""
        } else {
            problem = "Mikser potrzebuje zgody na nagrywanie dźwięku systemu (Ustawienia systemowe > Prywatność)."
        }
    }

    // MARK: Core Audio helpers

    private static func get<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ empty: T) -> T {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var v = empty, size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : empty
    }

    static func processObjects() -> [AudioObjectID] {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func pid(of obj: AudioObjectID) -> pid_t { get(obj, kAudioProcessPropertyPID, kAudioObjectPropertyScopeGlobal, pid_t(0)) }
    static func isRunningOutput(_ obj: AudioObjectID) -> Bool { get(obj, kAudioProcessPropertyIsRunningOutput, kAudioObjectPropertyScopeGlobal, UInt32(0)) != 0 }

    static func outputDevice() -> AudioObjectID { get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, AudioObjectID(0)) }

    static func outputUID() -> String {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(outputDevice(), &a, 0, nil, &size, &uid) == noErr, let s = uid?.takeRetainedValue() else { return "" }
        return s as String
    }

    static func mainVolume() -> Float { get(outputDevice(), kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput, Float32(0)) }

    static func setMainVolume(_ v: Float) {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value = Float32(max(0, min(1, v)))
        AudioObjectSetPropertyData(outputDevice(), &a, 0, nil, 4, &value)
    }

    static func isMuted() -> Bool { get(outputDevice(), kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, UInt32(0)) != 0 }

    static func setMute(_ on: Bool) {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var m = UInt32(on ? 1 : 0)
        AudioObjectSetPropertyData(outputDevice(), &a, 0, nil, 4, &m)
    }
}
