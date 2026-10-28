// Concierge Pokój - receives the room sound streamed by the phone app "Concierge Ucho" over the home Wi-Fi (raw 16 kHz PCM over TCP) and advertises itself with Bonjour so the phone finds it.
import Foundation
import Network

final class RemoteMic {
    var onChunk: (Data, Float) -> Void = { _, _ in }
    private var listener: NWListener?
    private var conn: NWConnection?
    private let queue = DispatchQueue(label: "room.remote-mic")
    private let lock = NSLock()
    private var buffer = Data()
    private var gotHeader = false
    private var last = Date.distantPast

    var active: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(last) < 1.5
    }

    func start(port: UInt16 = 47110) {
        guard let p = NWEndpoint.Port(rawValue: port), let l = try? NWListener(using: .tcp, on: p) else { NSLog("room: remote mic listener failed"); return }
        l.service = NWListener.Service(name: "MacPetite", type: "_gzowoear._tcp")
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { state in if case .failed(let e) = state { NSLog("room: remote mic listener: \(e)") } }
        l.start(queue: queue)
        listener = l
    }

    func send(_ line: String) {
        queue.async { [weak self] in
            guard let c = self?.conn else { NSLog("room: ear command dropped, phone not connected"); return }
            c.send(content: Data((line + "\n").utf8), completion: .contentProcessed { _ in })
            NSLog("room: ear command '\(line)'")
        }
    }

    private func accept(_ c: NWConnection) {
        conn?.cancel()
        conn = c
        buffer = Data()
        gotHeader = false
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.drop(c)
            default: break
            }
        }
        c.start(queue: queue)
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self, c === self.conn else { return }
            if let data, !data.isEmpty { self.consume(data) }
            if done || error != nil { self.drop(c); return }
            self.receive(c)
        }
    }

    private func drop(_ c: NWConnection) {
        guard c === conn else { return }
        conn = nil
        c.cancel()
        NSLog("room: remote mic disconnected")
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        if !gotHeader {
            guard let nl = buffer.firstIndex(of: 10) else { if buffer.count > 512 { buffer = Data() }; return }
            let header = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer = Data(buffer[buffer.index(after: nl)...])
            gotHeader = true
            NSLog("room: remote mic connected (\(header))")
        }
        while buffer.count >= 3200 {
            let chunk = Data(buffer.prefix(3200))
            buffer = Data(buffer.dropFirst(3200))
            lock.lock(); last = Date(); lock.unlock()
            onChunk(chunk, Self.level(chunk))
        }
    }

    private static func level(_ chunk: Data) -> Float {
        chunk.withUnsafeBytes { raw -> Float in
            let s = raw.bindMemory(to: Int16.self)
            var sum: Double = 0
            var i = 0
            while i < s.count { let v = Double(s[i]); sum += v * v; i += 4 }
            return Float(min(1, (sum / Double(max(1, s.count / 4))).squareRoot() / 32768 * 6))
        }
    }
}
