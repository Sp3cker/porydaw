import Foundation
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(ucrt)
    import ucrt
#endif

public struct WavExportOptions: Equatable, Sendable {
    public static let sampleRates = [32_000, 44_100, 48_000]
    public var sampleRate: Int
    public var loopCount: Int
    public var fadeoutSeconds: Double
    public var tailSeconds: Double
    public var resonanceSuppression: Bool

    public init(
        sampleRate: Int = 48_000, loopCount: Int = 2,
        fadeoutSeconds: Double = 5.0, tailSeconds: Double = 3.0,
        resonanceSuppression: Bool = false
    ) {
        self.sampleRate = sampleRate
        self.loopCount = loopCount
        self.fadeoutSeconds = fadeoutSeconds
        self.tailSeconds = tailSeconds
        self.resonanceSuppression = resonanceSuppression
    }
}

public struct WavExportTotals: Equatable, Sendable {
    public static let noFade = UInt64.max
    public let totalFrames: UInt64
    public let fadeStartFrame: UInt64

    public init(totalFrames: UInt64, fadeStartFrame: UInt64) {
        self.totalFrames = totalFrames
        self.fadeStartFrame = fadeStartFrame
    }

    public init(timeline: borrowing PlaybackTimeline, options: WavExportOptions) {
        self = Self.make(
            length: timeline.lengthSamples, loopStart: timeline.loopStartSample,
            loopEnd: timeline.loopEndSample, options: options)
    }

    private static func make(
        length: UInt64, loopStart: UInt64, loopEnd: UInt64,
        options: WavExportOptions
    ) -> Self {
        let rate = Double(options.sampleRate)
        if playbackHasLoop(startSample: loopStart, endSample: loopEnd) {
            let fadeStart = loopStart + UInt64(options.loopCount) * (loopEnd - loopStart)
            return Self(
                totalFrames: fadeStart + UInt64(options.fadeoutSeconds * rate + 0.5),
                fadeStartFrame: fadeStart)
        }
        return Self(
            totalFrames: length + UInt64(options.tailSeconds * rate + 0.5),
            fadeStartFrame: noFade)
    }

    public func gain(atFrame frame: UInt64) -> Float {
        guard frame >= fadeStartFrame, totalFrames > fadeStartFrame else { return 1 }
        return 1 - Float(frame - fadeStartFrame) / Float(totalFrames - fadeStartFrame)
    }

    public static func previewSeconds(
        timeline: borrowing PlaybackTimeline,
        options: WavExportOptions
    ) -> Int {
        let scale = Double(options.sampleRate) / timeline.sampleRate
        let length = UInt64(Double(timeline.lengthSamples) * scale)
        let hasLoop = timeline.hasLoop
        let start = hasLoop ? UInt64(Double(timeline.loopStartSample) * scale) : noFade
        let end = hasLoop ? UInt64(Double(timeline.loopEndSample) * scale) : noFade
        let totals = make(length: length, loopStart: start, loopEnd: end, options: options)
        return Int(Double(totals.totalFrames) / Double(options.sampleRate) + 0.5)
    }

    public static func clockText(seconds: Int) -> String {
        let remainder = seconds % 60
        return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
    }
}

public enum WavExportError: Error, Equatable, Sendable {
    case nothingToRender
    case exceedsRiffLimit
    case cannotWrite(path: String, reason: String)

    public var message: String {
        switch self {
        case .nothingToRender: "Nothing to render."
        case .exceedsRiffLimit: "The rendered file would exceed the 4 GB WAV limit — reduce the loop count."
        case .cannotWrite(let path, let reason): "Cannot write \(path): \(reason)"
        }
    }
}

public enum WavExportResult: Equatable, Sendable {
    case completed
    case cancelled
}

/// Owns the bounded, private offline render and its RIFF PCM16 output.
public enum WavExport {
    public static let chunkFrames = 4096

    public static func header(totals: WavExportTotals, sampleRate: Int) throws(WavExportError) -> [UInt8] {
        guard totals.totalFrames != 0 else { throw .nothingToRender }
        guard totals.totalFrames <= (UInt64(UInt32.max) - 36) / 4 else { throw .exceedsRiffLimit }
        let dataSize = UInt32(totals.totalFrames * 4)
        return [UInt8](unsafeUninitializedCapacity: 44) { buffer, initialized in
            var output = OutputSpan<UInt8>(buffer: buffer, initializedCount: 0)
            for byte in "RIFF".utf8 { output.append(byte) }
            putU32(36 + dataSize, to: &output)
            for byte in "WAVEfmt ".utf8 { output.append(byte) }
            putU32(16, to: &output)
            putU16(1, to: &output)
            putU16(2, to: &output)
            putU32(UInt32(sampleRate), to: &output)
            putU32(UInt32(sampleRate * 4), to: &output)
            putU16(4, to: &output)
            putU16(16, to: &output)
            for byte in "data".utf8 { output.append(byte) }
            putU32(dataSize, to: &output)
            initialized = output.count
        }
    }

    public static func render(
        to path: String, timeline: borrowing PlaybackTimeline,
        voices: UnsafeMutablePointer<ToneData>?, settings: AudioSettings,
        options: WavExportOptions,
        progress: (Double) -> Bool
    ) throws(WavExportError) -> WavExportResult {
        precondition(timeline.sampleRate == Double(options.sampleRate))
        let totals = WavExportTotals(timeline: timeline, options: options)
        let wavHeader = try header(totals: totals, sampleRate: options.sampleRate)
        guard let file = path.withCString({ fopen($0, "wb") }) else {
            throw .cannotWrite(path: path, reason: errnoText())
        }
        var fileOpen = true
        var keepFile = false
        defer {
            if fileOpen { _ = fclose(file) }
            if !keepFile { _ = path.withCString { remove($0) } }
        }
        try write(wavHeader, count: wavHeader.count, to: file, path: path)

        guard let engine = m4a_engine_create(Float(options.sampleRate)) else {
            throw .cannotWrite(path: path, reason: "Cannot initialize audio engine.")
        }
        defer { m4a_engine_free(engine) }
        AudioRenderEngine.configure(engine, voicegroup: voices, settings: settings)

        var left = [Float](repeating: 0, count: chunkFrames)
        var right = [Float](repeating: 0, count: chunkFrames)
        var interleaved = [Float](repeating: 0, count: chunkFrames * 2)
        var pcm = [UInt8](repeating: 0, count: chunkFrames * 4)
        var player = Sequencer()
        guard progress(0) else { return .cancelled }

        let suppressor =
            options.resonanceSuppression
            ? ResonanceSuppression(sampleRate: Float(options.sampleRate)) : nil
        suppressor?.setEnabled(true)
        var sourcePos: UInt64 = 0
        if let suppressor {
            var remaining = ResonanceSuppression.latency
            while remaining > 0 {
                let count = min(chunkFrames, remaining)
                renderSource(
                    count, engine: engine, timeline: timeline, totals: totals,
                    player: &player, sourcePos: &sourcePos, left: &left, right: &right,
                    interleaved: &interleaved, suppressor: suppressor)
                remaining -= count
            }
        }

        var position: UInt64 = 0
        while position < totals.totalFrames {
            let count = Int(min(UInt64(chunkFrames), totals.totalFrames - position))
            if let suppressor {
                renderSource(
                    count, engine: engine, timeline: timeline, totals: totals,
                    player: &player, sourcePos: &sourcePos, left: &left, right: &right,
                    interleaved: &interleaved, suppressor: suppressor)
            } else {
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        player.render(
                            engine: engine, timeline: timeline,
                            left: UnsafeMutableBufferPointer(start: l.baseAddress, count: count),
                            right: UnsafeMutableBufferPointer(start: r.baseAddress, count: count),
                            looping: timeline.hasLoop, muteMask: 0)
                    }
                }
            }
            do {
                var bytes = pcm.mutableSpan
                for frame in 0..<count {
                    let gain = totals.gain(atFrame: position + UInt64(frame))
                    let l = options.resonanceSuppression ? interleaved[2 * frame] : left[frame]
                    let r = options.resonanceSuppression ? interleaved[2 * frame + 1] : right[frame]
                    putU16(clampPCM16(l * gain), into: &bytes, at: 4 * frame)
                    putU16(clampPCM16(r * gain), into: &bytes, at: 4 * frame + 2)
                }
            }
            try write(pcm, count: count * 4, to: file, path: path)
            position += UInt64(count)
            guard progress(Double(position) / Double(totals.totalFrames)) else { return .cancelled }
        }
        if fclose(file) != 0 {
            fileOpen = false
            throw .cannotWrite(path: path, reason: errnoText())
        }
        fileOpen = false
        keepFile = true
        return .completed
    }

    private static func renderSource(
        _ count: Int, engine: UnsafeMutablePointer<M4AEngine>,
        timeline: borrowing PlaybackTimeline, totals: WavExportTotals,
        player: inout Sequencer, sourcePos: inout UInt64,
        left: inout [Float], right: inout [Float],
        interleaved: inout [Float], suppressor: ResonanceSuppression
    ) {
        let sourceCount = Int(min(UInt64(count), totals.totalFrames - sourcePos))
        if sourceCount > 0 {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    player.render(
                        engine: engine, timeline: timeline,
                        left: UnsafeMutableBufferPointer(start: l.baseAddress, count: sourceCount),
                        right: UnsafeMutableBufferPointer(start: r.baseAddress, count: sourceCount),
                        looping: timeline.hasLoop, muteMask: 0)
                }
            }
        }
        var l = left.mutableSpan
        var r = right.mutableSpan
        for frame in sourceCount..<count {
            l[frame] = 0
            r[frame] = 0
        }
        var samples = interleaved.mutableSpan
        for frame in 0..<count {
            samples[2 * frame] = left[frame]
            samples[2 * frame + 1] = right[frame]
        }
        interleaved.withUnsafeMutableBufferPointer {
            if let base = $0.baseAddress { suppressor.process(base, frames: UInt32(count)) }
        }
        sourcePos += UInt64(sourceCount)
    }

    /// Clamps scaled PCM samples to signed 16-bit bounds [-32768, 32767].
    private static func clampPCM16(_ sample: Float) -> UInt16 {
        let scaled = sample * 32767
        guard !scaled.isNaN else { return 0 }
        return UInt16(
            bitPattern: Int16(
                scaled.isInfinite
                    ? (scaled.sign == .minus ? -32768 : 32767)
                    : Int32(max(-32768, min(32767, scaled)))))
    }

    private static func putU16(_ value: UInt16, into bytes: inout MutableSpan<UInt8>, at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    private static func putU16(_ value: UInt16, to output: inout OutputSpan<UInt8>) {
        output.append(UInt8(truncatingIfNeeded: value))
        output.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func putU32(_ value: UInt32, to output: inout OutputSpan<UInt8>) {
        output.append(UInt8(truncatingIfNeeded: value))
        output.append(UInt8(truncatingIfNeeded: value >> 8))
        output.append(UInt8(truncatingIfNeeded: value >> 16))
        output.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private static func errnoText() -> String { String(cString: strerror(errno)) }

    private static func write(
        _ bytes: [UInt8], count: Int, to file: UnsafeMutablePointer<FILE>,
        path: String
    ) throws(WavExportError) {
        let failure = bytes.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return "empty output buffer" }
            var written = 0
            while written < count {
                let n = fwrite(base.advanced(by: written), 1, count - written, file)
                written += n
                if ferror(file) != 0 { return errnoText() }
                if n == 0 { return "short write" }
            }
            return nil
        }
        if let failure { throw .cannotWrite(path: path, reason: failure) }
    }
}
