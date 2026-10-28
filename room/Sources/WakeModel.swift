// Concierge Pokój - trained "Hej Gzowo" / "OK Gzowo" detector: openWakeWord's melspectrogram and speech-embedding models plus our own classifier, run with ONNX Runtime on 80 ms steps exactly like openWakeWord's streaming code.
import Foundation

final class OnnxRuntime {
    private let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?
    private var memory: OpaquePointer?

    init?() {
        guard let base = OrtGetApiBase(), let a = base.pointee.GetApi(UInt32(ORT_API_VERSION)) else { return nil }
        api = a
        guard ok(api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "room", &env)),
              ok(api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory)) else { return nil }
    }

    private func ok(_ status: OpaquePointer?) -> Bool {
        guard let status else { return true }
        if let msg = api.pointee.GetErrorMessage(status) { NSLog("room: onnx: \(String(cString: msg))") }
        api.pointee.ReleaseStatus(status)
        return false
    }

    func session(_ path: String) -> OpaquePointer? {
        var opts: OpaquePointer?
        guard ok(api.pointee.CreateSessionOptions(&opts)) else { return nil }
        defer { api.pointee.ReleaseSessionOptions(opts) }
        _ = ok(api.pointee.SetIntraOpNumThreads(opts, 1))
        _ = ok(api.pointee.SetSessionGraphOptimizationLevel(opts, ORT_ENABLE_ALL))
        var s: OpaquePointer?
        guard ok(api.pointee.CreateSession(env, path, opts, &s)) else { return nil }
        return s
    }

    func run(_ session: OpaquePointer, input: String, output: String, data: [Float], shape: [Int64]) -> [Float]? {
        var value: OpaquePointer?
        var result: [Float]?
        var data = data
        var shape = shape
        data.withUnsafeMutableBytes { buf in
            guard ok(api.pointee.CreateTensorWithDataAsOrtValue(memory, buf.baseAddress, buf.count, &shape, shape.count, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &value)) else { return }
            defer { api.pointee.ReleaseValue(value) }
            var out: OpaquePointer?
            let ran = input.withCString { inName -> Bool in
                output.withCString { outName -> Bool in
                    var inNames: [UnsafePointer<CChar>?] = [inName]
                    var outNames: [UnsafePointer<CChar>?] = [outName]
                    var inputs: [OpaquePointer?] = [value]
                    return ok(api.pointee.Run(session, nil, &inNames, &inputs, 1, &outNames, 1, &out))
                }
            }
            guard ran, let out else { return }
            defer { api.pointee.ReleaseValue(out) }
            var info: OpaquePointer?
            var count = 0
            guard ok(api.pointee.GetTensorTypeAndShape(out, &info)) else { return }
            _ = ok(api.pointee.GetTensorShapeElementCount(info, &count))
            api.pointee.ReleaseTensorTypeAndShapeInfo(info)
            var ptr: UnsafeMutableRawPointer?
            guard ok(api.pointee.GetTensorMutableData(out, &ptr)), let ptr else { return }
            result = Array(UnsafeBufferPointer(start: ptr.assumingMemoryBound(to: Float.self), count: count))
        }
        return result
    }
}

final class WakeModel {
    var onWake: (Float) -> Void = { _ in }
    var threshold: Float
    private let ort: OnnxRuntime
    private let mel: OpaquePointer
    private let emb: OpaquePointer
    private let cls: OpaquePointer
    private var pending: [Float] = []
    private var raw: [Float] = Array(repeating: 0, count: 1760)
    private var melFrames: [[Float]] = Array(repeating: Array(repeating: 1, count: 32), count: 76)
    private var features: [[Float]] = []
    private var steps = 0
    private var lastWake = -100
    private(set) var lastScore: Float = 0

    init?(dir: URL, threshold: Float) {
        guard let o = OnnxRuntime(),
              let m = o.session(dir.appendingPathComponent("melspectrogram.onnx").path),
              let e = o.session(dir.appendingPathComponent("embedding_model.onnx").path),
              let c = o.session(dir.appendingPathComponent("gzowo_wake.onnx").path) else { return nil }
        ort = o; mel = m; emb = e; cls = c
        self.threshold = threshold
    }

    func accept(_ pcm16: Data) {
        pcm16.withUnsafeBytes { raw in
            for s in raw.bindMemory(to: Int16.self) { pending.append(Float(s)) }
        }
        while pending.count >= 1280 {
            step(Array(pending.prefix(1280)))
            pending.removeFirst(1280)
        }
    }

    private func step(_ chunk: [Float]) {
        raw.append(contentsOf: chunk)
        if raw.count > 3200 { raw.removeFirst(raw.count - 3200) }
        guard let spec = ort.run(mel, input: "input", output: "output", data: Array(raw.suffix(1760)), shape: [1, 1760]) else { return }
        for f in 0..<(spec.count / 32) {
            melFrames.append(spec[(f * 32)..<(f * 32 + 32)].map { $0 / 10 + 2 })
        }
        if melFrames.count > 120 { melFrames.removeFirst(melFrames.count - 120) }
        guard let e = ort.run(emb, input: "input_1", output: "conv2d_19", data: melFrames.suffix(76).flatMap { $0 }, shape: [1, 76, 32, 1]), e.count == 96 else { return }
        features.append(e)
        if features.count > 32 { features.removeFirst(features.count - 32) }
        steps += 1
        guard features.count >= 16, steps > 20,
              let y = ort.run(cls, input: "x", output: "y", data: features.suffix(16).flatMap { $0 }, shape: [1, 16, 96]), let score = y.first else { return }
        lastScore = score
        if score >= threshold && steps - lastWake > 25 {
            lastWake = steps
            onWake(score)
        }
    }
}
