import Foundation
import Synchronization

public struct ResonanceParameters {
    public var gDb: Float = 1.9
    public var guardDb: Float = 6
    public var timingMs: Float = 150
    public var knotDepthDb: [Float] = [0, 0, 0, 0, 0, 10, 10, 10, 10, 10, 10, 10]
    public var knotActive: [Bool] = [false, false, false, false, false, false,
                                     false, true, true, true, true, false]
    public var forceMaskOne = false
    public init() {}
}

/// Device-rate, stereo-linked STFT suppression. Parameters are cold-only;
/// enable requests are single-writer atomic; process/reset belong to the audio thread.
public final class ResonanceSuppression {
    public static let frameSize = 2048
    public static let hopSize = 1024
    public static let latency = 2047

    public private(set) var parameters = ResonanceParameters()
    public var enabled: Bool { requestedEnabled.load(ordering: .acquiring) }

    public init(sampleRate: Float) {
        self.sampleRate = Double(sampleRate)
        storage = .allocate(capacity: Self.storageCount)
        storage.initialize(repeating: 0, count: Self.storageCount)
        window = storage
        twiddleReal = window + 2048
        twiddleImag = twiddleReal + 1024
        input = twiddleImag + 1024
        output = input + 4096
        realL = output + 4096
        imagL = realL + 2048
        realR = imagL + 2048
        imagR = realR + 2048
        depth = imagR + 2048
        level = depth + 1025
        gain = level + 1025
        mask = gain + 1025
        bitReverse = .allocate(capacity: 2048)
        bitReverse.initialize(repeating: 0, count: 2048)
        for n in 0..<2048 {
            let phase = 2 * Double.pi * Double(n) / 2048
            window[n] = sqrt(0.5 - 0.5 * cos(phase))
            var value = n
            var reversed = 0
            for _ in 0..<11 {
                reversed = (reversed << 1) | (value & 1)
                value >>= 1
            }
            bitReverse[n] = reversed
        }
        for k in 0..<1024 {
            let phase = -2 * Double.pi * Double(k) / 2048
            twiddleReal[k] = cos(phase)
            twiddleImag[k] = sin(phase)
        }
        rebuildParameters()
        reset()
    }

    deinit {
        bitReverse.deinitialize(count: 2048)
        bitReverse.deallocate()
        storage.deinitialize(count: Self.storageCount)
        storage.deallocate()
    }

    public func setEnabled(_ enabled: Bool) {
        requestedEnabled.store(enabled, ordering: .releasing)
        requestedGeneration.wrappingAdd(1, ordering: .releasing)
    }

    public func setParameters(_ parameters: ResonanceParameters) {
        precondition(parameters.knotDepthDb.count == 12 && parameters.knotActive.count == 12)
        self.parameters = parameters
        rebuildParameters()
    }

    public func binGainDb(_ bin: Int) -> Double {
        guard bin >= 0 && bin <= 1024 else { return 0 }
        return gain[bin]
    }

    public func reset() {
        input.update(repeating: 0, count: 4096)
        output.update(repeating: 0, count: 4096)
        gain.update(repeating: 0, count: 1025)
        mask.update(repeating: 1, count: 1025)
        count = 1024
    }

    public func process(_ interleaved: UnsafeMutablePointer<Float>, frames: UInt32) {
        let generation = requestedGeneration.load(ordering: .acquiring)
        if generation != appliedGeneration {
            let requested = requestedEnabled.load(ordering: .acquiring)
            appliedGeneration = generation
            if requested != appliedEnabled {
                appliedEnabled = requested
                reset()
            }
        }
        guard appliedEnabled else { return }
        for i in 0..<Int(frames) {
            let slot = Int(count % 2048)
            input[2 * slot] = Double(interleaved[2 * i])
            input[2 * slot + 1] = Double(interleaved[2 * i + 1])
            count += 1
            if count >= 2048 && count % 1024 == 0 { processHop(start: count - 2048) }
            if count >= 3072 {
                let out = Int((count - 2048) % 2048)
                interleaved[2 * i] = Float(output[2 * out])
                interleaved[2 * i + 1] = Float(output[2 * out + 1])
                output[2 * out] = 0
                output[2 * out + 1] = 0
            } else {
                interleaved[2 * i] = 0
                interleaved[2 * i + 1] = 0
            }
        }
    }

    // One allocation owns all Double scratch; these typed pointers are disjoint
    // slices, never rebound and never escape the owner's lifetime. No hot Arrays.
    private static let storageCount = 2048 + 2048 + 8192 + 8192 + 4100
    private let storage: UnsafeMutablePointer<Double>
    private let window, twiddleReal, twiddleImag: UnsafeMutablePointer<Double>
    private let input, output: UnsafeMutablePointer<Double>
    private let realL, imagL, realR, imagR: UnsafeMutablePointer<Double>
    private let depth, level, gain, mask: UnsafeMutablePointer<Double>
    private let bitReverse: UnsafeMutablePointer<Int>
    private let sampleRate: Double
    private let requestedEnabled = Atomic<Bool>(false)
    private let requestedGeneration = Atomic<UInt32>(0)
    private var appliedEnabled = false
    private var appliedGeneration: UInt32 = 0
    private var count: UInt64 = 1024
    private var alphaAttack = 0.0
    private var alphaRelease = 0.0
    private var stepCap = 0.0
    private let calibration = Double.pi * Double.pi / (2048 * 2048)

    private func fft(_ real: UnsafeMutablePointer<Double>, _ imag: UnsafeMutablePointer<Double>, inverse: Bool) {
        for i in 0..<2048 {
            let j = bitReverse[i]
            if i < j {
                let r = real[i], v = imag[i]
                real[i] = real[j]; real[j] = r
                imag[i] = imag[j]; imag[j] = v
            }
        }
        var length = 2
        while length <= 2048 {
            let half = length / 2, step = 2048 / length
            for block in stride(from: 0, to: 2048, by: length) {
                for j in 0..<half {
                    let wr = twiddleReal[j * step]
                    let wi = inverse ? -twiddleImag[j * step] : twiddleImag[j * step]
                    let even = block + j, odd = even + half
                    let tr = real[odd] * wr - imag[odd] * wi
                    let ti = real[odd] * wi + imag[odd] * wr
                    let er = real[even], ei = imag[even]
                    real[even] = er + tr; imag[even] = ei + ti
                    real[odd] = er - tr; imag[odd] = ei - ti
                }
            }
            length <<= 1
        }
        if inverse {
            for i in 0..<2048 { real[i] /= 2048; imag[i] /= 2048 }
        }
    }

    private func processHop(start: UInt64) {
        for n in 0..<2048 {
            let slot = Int((start + UInt64(n)) % 2048)
            realL[n] = input[2 * slot] * window[n]; imagL[n] = 0
            realR[n] = input[2 * slot + 1] * window[n]; imagR[n] = 0
        }
        fft(realL, imagL, inverse: false)
        fft(realR, imagR, inverse: false)
        for k in 0...1024 {
            level[k] = -120
            if k != 0 && k != 1024 {
                let left = realL[k] * realL[k] + imagL[k] * imagL[k]
                let right = realR[k] * realR[k] + imagR[k] * imagR[k]
                level[k] = 10 * log10(0.5 * (left + right) * calibration + 1e-24)
            }
        }
        for k in 0...1024 {
            var target = 0.0
            if k != 0 && k != 1024 {
                var sum = 0.0
                var neighbors = 0
                for offset in -6...6 where offset <= -3 || offset >= 3 {
                    let n = k + offset
                    if n >= 1 && n <= 1023 { sum += level[n]; neighbors += 1 }
                }
                let reference = max(-120, sum / Double(neighbors))
                let excess = level[k] - (reference + Double(parameters.guardDb))
                var law = 0.0
                if excess > 6 {
                    let t = min(1, (excess - 6) / 14)
                    law = 1.25 * t * t * (3 - 2 * t)
                }
                target = -2.5 * depth[k] * law
            }
            let current = gain[k]
            let alpha = target < current ? alphaAttack : alphaRelease
            gain[k] = current + min(stepCap, max(-stepCap, (target - current) * alpha))
            mask[k] = parameters.forceMaskOne ? 1 : pow(10, gain[k] / 20)
        }
        for k in 0...1024 {
            let value = mask[k]
            realL[k] *= value; imagL[k] *= value
            realR[k] *= value; imagR[k] *= value
            if k != 0 && k != 1024 {
                let mirror = 2048 - k
                realL[mirror] *= value; imagL[mirror] *= value
                realR[mirror] *= value; imagR[mirror] *= value
            }
        }
        fft(realL, imagL, inverse: true)
        fft(realR, imagR, inverse: true)
        for n in 0..<2048 {
            let slot = Int((start + UInt64(n)) % 2048)
            output[2 * slot] += realL[n] * window[n]
            output[2 * slot + 1] += realR[n] * window[n]
        }
    }

    private func rebuildParameters() {
        if sampleRate <= 0 {
            alphaAttack = 0; alphaRelease = 0; stepCap = 0
        } else {
            let dt = 1024 / sampleRate
            let timing = Double(parameters.timingMs) * 0.001
            alphaAttack = timing > 0 ? 1 - exp(-dt / timing) : 1
            alphaRelease = timing > 0 ? 1 - exp(-dt / (4 * timing)) : 1
            stepCap = 100 * dt
        }
        let frequencies: [Double] = [65, 125, 250, 400, 630, 1000, 1600, 2100, 4000, 6300, 10000, 16000]
        var effective = [Double](repeating: 0, count: 12)
        for i in 0..<12 {
            let active = parameters.knotActive[i] && frequencies[i] < 0.5 * sampleRate
            let value = active ? Double(parameters.gDb) * Double(parameters.knotDepthDb[i]) / 10 : 0
            effective[i] = min(10, max(0, value))
        }
        for k in 0...1024 {
            let frequency = Double(k) * sampleRate / 2048
            var value = effective[0]
            if frequency >= frequencies[11] { value = effective[11] }
            else if frequency > frequencies[0] {
                var upper = 1
                while upper < 12 && frequency > frequencies[upper] { upper += 1 }
                if upper < 12 {
                    let lowerLog = log(frequencies[upper - 1])
                    let amount = (log(frequency) - lowerLog) / (log(frequencies[upper]) - lowerLog)
                    value = effective[upper - 1] + amount * (effective[upper] - effective[upper - 1])
                }
            }
            depth[k] = value
        }
    }
}
