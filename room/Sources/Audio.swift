// Concierge Pokój - microphone at 16 kHz in 100 ms chunks, 24 kHz speech playback and recorded sounds; capture and playback run on separate engines so a Bluetooth speaker works with the built-in mic.
import AVFoundation
import Accelerate

final class AudioIO {
    var onChunk: (Data, Float) -> Void = { _, _ in }
    var onSpeechIdle: () -> Void = {}

    private var capture: AVAudioEngine?
    private let playback = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let speechFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
    private var queued = 0
    private var generation = 0
    private var carry = Data()
    private var effects: [String: AVAudioPlayer] = [:]
    private var observers: [NSObjectProtocol] = []

    var speaking: Bool { queued > 0 }
    private let muted = ProcessInfo.processInfo.environment["ROOM_MUTE"] != nil

    func start() throws {
        playback.attach(player)
        playback.connect(player, to: playback.mainMixerNode, format: speechFormat)
        if muted { player.volume = 0 }
        try startPlayback()
        if ProcessInfo.processInfo.environment["ROOM_NO_MIC"] == nil { try startCapture() }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: playback, queue: .main) { [weak self] _ in
            try? self?.startPlayback()
        })
    }

    private func startPlayback() throws {
        playback.stop()
        playback.prepare()
        try playback.start()
        player.play()
    }

    private func startCapture() throws {
        capture?.inputNode.removeTap(onBus: 0)
        capture?.stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "room", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mikrofon jest niedostępny"])
        }
        converter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
        let ratio = 16000 / inFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(inFormat.sampleRate / 10), format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
            var consumed = false
            var err: NSError?
            let status = converter.convert(to: out, error: &err) { _, outStatus in
                if consumed { outStatus.pointee = .noDataNow; return nil }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, out.frameLength > 0, let ch = out.int16ChannelData?[0] else { return }
            self.carry.append(Data(bytes: ch, count: Int(out.frameLength) * 2))
            while self.carry.count >= 3200 {
                let chunk = self.carry.prefix(3200)
                self.carry.removeFirst(3200)
                self.onChunk(Data(chunk), Self.level(chunk))
            }
        }
        engine.prepare()
        try engine.start()
        capture = engine
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            try? self?.startCapture()
        })
    }

    private static func level(_ chunk: Data) -> Float {
        chunk.withUnsafeBytes { raw -> Float in
            guard let p = raw.bindMemory(to: Int16.self).baseAddress else { return 0 }
            let n = chunk.count / 2
            var f = [Float](repeating: 0, count: n)
            vDSP_vflt16(p, 1, &f, 1, vDSP_Length(n))
            var rms: Float = 0
            vDSP_rmsqv(f, 1, &rms, vDSP_Length(n))
            return min(1, rms / 32768 * 6)
        }
    }

    func playSpeech(_ pcm16: Data) {
        let n = pcm16.count / 2
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: speechFormat, frameCapacity: AVAudioFrameCount(n)), let dst = buf.floatChannelData?[0] else { return }
        buf.frameLength = AVAudioFrameCount(n)
        pcm16.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress else { return }
            vDSP_vflt16(src, 1, dst, 1, vDSP_Length(n))
            var scale: Float = 1 / 32768
            vDSP_vsmul(dst, 1, &scale, dst, 1, vDSP_Length(n))
        }
        if !player.isPlaying { player.play() }
        queued += 1
        let gen = generation
        player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.queued = max(0, self.queued - 1)
                if self.queued == 0 { self.onSpeechIdle() }
            }
        }
    }

    func stopSpeech() {
        generation += 1
        queued = 0
        player.stop()
        player.play()
    }

    func effect(_ name: String, loops: Int = 0, volume: Float = 1) {
        let p: AVAudioPlayer
        if let existing = effects[name] {
            p = existing
        } else {
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "sounds"),
                  let made = try? AVAudioPlayer(contentsOf: url) else { return }
            effects[name] = made
            p = made
        }
        p.numberOfLoops = loops
        p.volume = muted ? 0 : volume
        p.currentTime = 0
        p.play()
    }

    func stopEffect(_ name: String) { effects[name]?.stop() }

    func effectPlaying(_ name: String) -> Bool { effects[name]?.isPlaying ?? false }
}
