import Foundation

struct SampleFixtureSpec {
    var formatTag: UInt16 = 1
    var bits: UInt16 = 8
    var channels: UInt16 = 1
    var rate: UInt32 = 22050
    var samples: [UInt8] = []
    var withSmpl = true
    var unityKey: UInt32 = 60
    var pitchFraction: UInt32 = 0
    var numLoops = 0
    var loopType: UInt32 = 0
    var loopStart: UInt32 = 0
    var loopEndInclusive: UInt32 = 0
    var agbp: UInt32 = 0
    var agbl: UInt32 = 0
}

func putU16(_ bytes: inout [UInt8], _ value: UInt16) {
    bytes.append(UInt8(truncatingIfNeeded: value))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
}
func putU32(_ bytes: inout [UInt8], _ value: UInt32) {
    putU16(&bytes, UInt16(truncatingIfNeeded: value))
    putU16(&bytes, UInt16(truncatingIfNeeded: value >> 16))
}
func getU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3])
        << 24
}
func fixtureWav(_ spec: SampleFixtureSpec) -> Data {
    let align = spec.channels * (spec.bits / 8)
    var bytes = Array("RIFF".utf8) + [UInt8](repeating: 0, count: 4) + Array("WAVEfmt ".utf8)
    putU32(&bytes, 16)
    putU16(&bytes, spec.formatTag)
    putU16(&bytes, spec.channels)
    putU32(&bytes, spec.rate)
    putU32(&bytes, spec.rate * UInt32(align))
    putU16(&bytes, align)
    putU16(&bytes, spec.bits)
    bytes += Array("data".utf8)
    putU32(&bytes, UInt32(spec.samples.count))
    bytes += spec.samples
    if spec.samples.count & 1 != 0 { bytes.append(0) }
    if spec.withSmpl {
        bytes += Array("smpl".utf8)
        putU32(&bytes, UInt32(36 + 24 * spec.numLoops))
        for field: UInt32 in [0, 0, 0, spec.unityKey, spec.pitchFraction, 0, 0, UInt32(spec.numLoops), 0] {
            putU32(&bytes, field)
        }
        for index in 0..<spec.numLoops {
            for field: UInt32 in [UInt32(index), spec.loopType, spec.loopStart, spec.loopEndInclusive, 0, 0] {
                putU32(&bytes, field)
            }
        }
    }
    if spec.agbp != 0 {
        bytes += Array("agbp".utf8)
        putU32(&bytes, 4)
        putU32(&bytes, spec.agbp)
    }
    if spec.agbl != 0 {
        bytes += Array("agbl".utf8)
        putU32(&bytes, 4)
        putU32(&bytes, spec.agbl)
    }
    let size = UInt32(bytes.count - 8)
    for index in 0..<4 { bytes[4 + index] = UInt8(truncatingIfNeeded: size >> (index * 8)) }
    return Data(bytes)
}

struct AiffFixtureSpec {
    var channels: UInt16 = 1
    var numFrames: UInt32 = 0
    var sampleSize: UInt16 = 16
    var rate = 22050.0
    var baseNote = 60
    var detune = 0
    var loop = false
    var loopStartPos: UInt32 = 0
    var loopEndPos: UInt32 = 0
    var ssnd: [UInt8] = []
}
func putBe16(_ bytes: inout [UInt8], _ value: UInt16) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
}
func putBe32(_ bytes: inout [UInt8], _ value: UInt32) {
    putBe16(&bytes, UInt16(truncatingIfNeeded: value >> 16))
    putBe16(&bytes, UInt16(truncatingIfNeeded: value))
}
func fixtureAiff(_ spec: AiffFixtureSpec) -> Data {
    var bytes = Array("FORM".utf8) + [UInt8](repeating: 0, count: 4) + Array("AIFFCOMM".utf8)
    putBe32(&bytes, 18)
    putBe16(&bytes, spec.channels)
    putBe32(&bytes, spec.numFrames)
    putBe16(&bytes, spec.sampleSize)
    let exponent = Int(floor(log2(spec.rate)))
    let mantissa = UInt64(spec.rate * pow(2, Double(63 - exponent)))
    putBe16(&bytes, UInt16(exponent + 16383))
    for shift in (0..<8).reversed() { bytes.append(UInt8(truncatingIfNeeded: mantissa >> (shift * 8))) }
    if spec.loop {
        bytes += Array("MARK".utf8)
        putBe32(&bytes, 18)
        putBe16(&bytes, 2)
        for (id, position): (UInt16, UInt32) in [(1, spec.loopStartPos), (2, spec.loopEndPos)] {
            putBe16(&bytes, id)
            putBe32(&bytes, position)
            bytes += [0, 0]
        }
    }
    bytes += Array("INST".utf8)
    putBe32(&bytes, 20)
    bytes += [UInt8(truncatingIfNeeded: spec.baseNote), UInt8(truncatingIfNeeded: spec.detune)]
    bytes += [UInt8](repeating: 0, count: 6)
    putBe16(&bytes, spec.loop ? 1 : 0)
    putBe16(&bytes, 1)
    putBe16(&bytes, 2)
    bytes += [UInt8](repeating: 0, count: 6)
    bytes += Array("SSND".utf8)
    putBe32(&bytes, UInt32(spec.ssnd.count + 8))
    putBe32(&bytes, 0)
    putBe32(&bytes, 0)
    bytes += spec.ssnd
    if spec.ssnd.count & 1 != 0 { bytes.append(0) }
    let size = UInt32(bytes.count - 8)
    for index in 0..<4 { bytes[4 + index] = UInt8(truncatingIfNeeded: size >> ((3 - index) * 8)) }
    return Data(bytes)
}
func preparedSampleWav() -> Data {
    var spec = SampleFixtureSpec()
    spec.rate = 13240
    spec.samples = (0..<64).map { UInt8($0 * 2) }
    spec.unityKey = 58
    spec.pitchFraction = 0x4000_0000
    spec.numLoops = 1
    spec.loopStart = 8
    spec.loopEndInclusive = 31
    spec.agbp = 15_000_000
    spec.agbl = 64
    return fixtureWav(spec)
}
func genSine(_ rate: Double, _ freq: Double, _ seconds: Double, _ amp: Double) -> [Float] {
    (0..<Int(rate * seconds)).map { Float(amp * sin(2 * .pi * freq * Double($0) / rate)) }
}
func genSineFast(_ rate: Double, _ freq: Double, _ seconds: Double, _ amp: Double) -> [Float] {
    let r = Float(rate)
    let f = Float(freq)
    let a = Float(amp)
    return (0..<Int(rate * seconds)).map { a * sin(2 * Float.pi * f * Float($0) / r) }
}
func rmsOf(_ values: [Float], _ from: Int, _ to: Int) -> Double {
    guard to > from else { return 0 }
    return sqrt(values[from..<to].reduce(0.0) { $0 + Double($1) * Double($1) } / Double(to - from))
}
func toneAmp(_ values: [Float], _ rate: Double, _ frequency: Double, _ from: Int, _ to: Int) -> Double {
    var real = 0.0
    var imaginary = 0.0
    var weight = 0.0
    let span = Double(to - from)
    for index in from..<to {
        let w = 0.5 * (1 - cos(2 * .pi * Double(index - from) / span))
        let phase = 2 * Double.pi * frequency * Double(index) / rate
        real += Double(values[index]) * w * cos(phase)
        imaginary += Double(values[index]) * w * sin(phase)
        weight += w
    }
    return 2 * hypot(real, imaginary) / weight
}
func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count & 1 != 0 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}
func genSaw(_ rate: Double, _ freq: Double, _ seconds: Double, _ amp: Double) -> [Float] {
    var result = [Float](repeating: 0, count: Int(rate * seconds))
    var harmonic = 1
    while freq * Double(harmonic) < 0.45 * rate {
        for index in result.indices {
            result[index] += Float(
                amp * 2 / .pi * sin(2 * .pi * freq * Double(harmonic) * Double(index) / rate) / Double(harmonic))
        }
        harmonic += 1
    }
    return result
}
func centsOff(_ frequency: Double, _ reference: Double) -> Double { 1200 * log2(frequency / reference) }
