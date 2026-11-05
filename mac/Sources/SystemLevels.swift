// Gzowo Concierge for macOS - volume, screen brightness and keyboard light: takes over their keys so each change shows on the island instead of the system bezel.
import AppKit
import AudioToolbox
import CoreAudio

enum LevelKind: Equatable { case volume, brightness, keyboard }

private enum Key {
    static let soundUp: Int32 = 0, soundDown: Int32 = 1, brightnessUp: Int32 = 2, brightnessDown: Int32 = 3, mute: Int32 = 7
    static let play: Int32 = 16, next: Int32 = 17, previous: Int32 = 18, fast: Int32 = 19, rewind: Int32 = 20
    static let lightUp: Int32 = 21, lightDown: Int32 = 22, lightToggle: Int32 = 23
}

struct LevelEvent: Equatable {
    var kind: LevelKind
    var value: Float
    var muted = false
    var device = ""
    var stamp = Date()
}

private final class AudioOut {
    private var listening: AudioObjectID = 0
    var onChange: () -> Void = {}

    var device: AudioObjectID {
        var dev = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
        return dev
    }

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    var canControl: Bool {
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume), settable = DarwinBoolean(false)
        return AudioObjectHasProperty(device, &a) && AudioObjectIsPropertySettable(device, &a, &settable) == noErr && settable.boolValue
    }

    var volume: Float {
        get {
            var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume), v = Float32(0), size = UInt32(4)
            return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v : 0
        }
        set {
            var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume), v = Float32(max(0, min(1, newValue)))
            AudioObjectSetPropertyData(device, &a, 0, nil, 4, &v)
        }
    }

    var muted: Bool {
        get {
            var a = address(kAudioDevicePropertyMute), m = UInt32(0), size = UInt32(4)
            return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &m) == noErr && m != 0
        }
        set {
            var a = address(kAudioDevicePropertyMute), m = UInt32(newValue ? 1 : 0)
            if AudioObjectHasProperty(device, &a) { AudioObjectSetPropertyData(device, &a, 0, nil, 4, &m) }
        }
    }

    var name: String {
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var n: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &n) == noErr, let s = n?.takeRetainedValue() else { return "" }
        return s as String
    }

    var builtIn: Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var t = UInt32(0), size = UInt32(4)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &t) == noErr && t == kAudioDeviceTransportTypeBuiltIn
    }

    func listen() {
        var sys = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &sys, .main) { [weak self] _, _ in self?.attach(); self?.onChange() }
        attach()
    }

    private func attach() {
        let dev = device
        guard dev != listening else { return }
        listening = dev
        for sel in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var a = address(sel)
            guard AudioObjectHasProperty(dev, &a) else { continue }
            AudioObjectAddPropertyListenerBlock(dev, &a, .main) { [weak self] _, _ in
                guard let self, self.listening == dev else { return }
                self.onChange()
            }
        }
    }
}

private final class ScreenLight {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let getFn: Get?
    private let setFn: Set?

    init() {
        let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getFn = h.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
        setFn = h.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }
    }

    private var display: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8), n = UInt32(0)
        CGGetOnlineDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    var available: Bool { getFn != nil && setFn != nil && brightness != nil }

    var brightness: Float? {
        guard let getFn, let d = display else { return nil }
        var b = Float(-1)
        return getFn(d, &b) == 0 && b >= 0 ? b : nil
    }

    func setBrightness(_ v: Float) {
        guard let setFn, let d = display else { return }
        _ = setFn(d, max(0, min(1, v)))
    }
}

private final class KeyLight {
    private typealias GetF = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetF = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private var client: NSObject?
    private var id: UInt64 = 1
    private var getter: GetF?
    private var setter: SetF?
    private var remembered: Float = 0.5

    init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }
        let c = cls.init()
        let g = NSSelectorFromString("brightnessForKeyboard:"), s = NSSelectorFromString("setBrightness:forKeyboard:")
        guard c.responds(to: g), c.responds(to: s) else { return }
        if let ids = c.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber], let first = ids.first { id = first.uint64Value }
        getter = unsafeBitCast(class_getMethodImplementation(cls, g), to: GetF.self)
        setter = unsafeBitCast(class_getMethodImplementation(cls, s), to: SetF.self)
        client = c
    }

    var available: Bool { client != nil }

    var level: Float {
        get { client.flatMap { c in getter?(c, NSSelectorFromString("brightnessForKeyboard:"), id) } ?? 0 }
        set { if let c = client { _ = setter?(c, NSSelectorFromString("setBrightness:forKeyboard:"), max(0, min(1, newValue)), id) } }
    }

    func toggle() {
        if level > 0.01 { remembered = level; level = 0 } else { level = max(remembered, 0.25) }
    }
}

final class SystemLevels {
    var onChange: (LevelEvent) -> Void = { _ in }
    var onMediaKey: () -> Void = {}
    private let audio = AudioOut()
    private let screen = ScreenLight()
    private let keys = KeyLight()
    fileprivate var tap: CFMachPort?
    private var lastVolume: (Float, Bool, String)?
    private var quietUntil = Date.distantPast
    private var retry: Timer?
    private let enabledKey = "systemLevelsOnIsland"

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey); if let tap { CGEvent.tapEnable(tap: tap, enable: newValue) } }
    }

    func start() {
        audio.onChange = { [weak self] in self?.audioChanged() }
        audio.listen()
        lastVolume = (audio.volume, audio.muted, audio.name)
        quietUntil = Date().addingTimeInterval(2)
        installTap()
    }

    private func installTap() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            retry?.invalidate()
            retry = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.installTap() }
            return
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        let thread = Thread { [weak self] in
            guard let self else { return }
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(1 << 14), callback: levelTapCallback, userInfo: me) else { return }
            self.tap = port
            let src = CFMachPortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: port, enable: self.enabled)
            CFRunLoopRun()
        }
        thread.name = "fun.gzowo.concierge.levels"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard enabled, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return false }
        let data = ns.data1
        let code = Int32((data & 0xFFFF_0000) >> 16)
        let down = ((data & 0xFF00) >> 8) == 0xA
        let flags = event.flags
        let option = flags.contains(.maskAlternate), shift = flags.contains(.maskShift)
        if option && !shift { return false }
        let steps: Float = option && shift ? 64 : 16
        switch code {
        case Key.soundUp, Key.soundDown, Key.mute:
            guard audio.canControl else { return false }
            if down { DispatchQueue.main.async { self.volumeKey(code, steps: steps, shift: shift) } }
            return true
        case Key.brightnessUp, Key.brightnessDown:
            guard screen.available else { return false }
            if down { DispatchQueue.main.async { self.brightnessKey(up: code == Key.brightnessUp, steps: steps) } }
            return true
        case Key.lightUp, Key.lightDown, Key.lightToggle:
            guard keys.available else { return false }
            if down { DispatchQueue.main.async { self.keyboardKey(code, steps: steps) } }
            return true
        case Key.play, Key.next, Key.previous, Key.fast, Key.rewind:
            if down { DispatchQueue.main.async { self.onMediaKey() } }
            return false
        default:
            return false
        }
    }

    private static func stepped(_ v: Float, _ dir: Float, _ steps: Float) -> Float {
        max(0, min(1, ((v * steps).rounded() + dir) / steps))
    }

    private func volumeKey(_ code: Int32, steps: Float, shift: Bool) {
        if code == Key.mute {
            audio.muted.toggle()
        } else {
            let up = code == Key.soundUp
            let next = Self.stepped(audio.volume, up ? 1 : -1, steps)
            if up && audio.muted { audio.muted = false }
            audio.volume = next
            feedback(shift: shift)
        }
        publishVolume(force: true)
    }

    private func feedback(shift: Bool) {
        let on = (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.sound.beep.feedback"] as? Int ?? 0) == 1
        guard on != shift, !audio.muted else { return }
        NSSound(named: "Pop")?.play()
    }

    private func audioChanged() {
        guard Date() > quietUntil else { lastVolume = (audio.volume, audio.muted, audio.name); return }
        publishVolume(force: false)
    }

    private func publishVolume(force: Bool) {
        let v = audio.volume, m = audio.muted, n = audio.name
        if !force, let last = lastVolume, abs(last.0 - v) < 0.004, last.1 == m, last.2 == n { return }
        let deviceChanged = lastVolume.map { $0.2 != n } ?? false
        lastVolume = (v, m, n)
        onChange(LevelEvent(kind: .volume, value: v, muted: m, device: deviceChanged || !audio.builtIn ? n : ""))
    }

    private func brightnessKey(up: Bool, steps: Float) {
        guard let b = screen.brightness else { return }
        let next = Self.stepped(b, up ? 1 : -1, steps)
        screen.setBrightness(next)
        onChange(LevelEvent(kind: .brightness, value: next))
    }

    private func keyboardKey(_ code: Int32, steps: Float) {
        if code == Key.lightToggle { keys.toggle() }
        else { keys.level = Self.stepped(keys.level, code == Key.lightUp ? 1 : -1, steps) }
        onChange(LevelEvent(kind: .keyboard, value: keys.level))
    }

    fileprivate func reenable() {
        if let tap, enabled { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

private func levelTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let me = Unmanaged<SystemLevels>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { me.reenable(); return Unmanaged.passUnretained(event) }
    return me.handle(event) ? nil : Unmanaged.passUnretained(event)
}
