import Foundation
import PorydawSample
@testable import SwiftCoreCheckLogic

public func runRenderPipelineChecks(_ report: CheckReport) {
    renderDeterminism(report)
    renderLoopGeometry(report)
    renderRiffPadding(report)
    renderRetune(report)
    renderCrossfade(report)
    renderCompressed(report)
    renderSoundFont(report)
    renderCorpus(report)
    renderZeroCrossing(report)
    renderSlice(report)
    renderRatePolicy(report)
}

func importedHiRes() throws -> ImportedSample {
    try SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav")
}

private func renderDeterminism(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::dspDeterminism")
    guard let source = try? importedHiRes() else {
        check.expect(false, message: "high resolution fixture imports for determinism")
        return
    }
    check.expect(
        SampleDocument.defaultParams(for: source).targetRate == 13379, message: "fresh high-rate default caps at 13379")
    var low = source
    low.sampleRate = 8000
    low.gbaReady = false
    check.expect(SampleDocument.defaultParams(for: low).targetRate == 8000, message: "low-rate default remains 8000")
    var params = SampleDocument.defaultParams(for: source)
    params.cropStart = 100
    params.cropEnd = 11500
    params.targetRate = 13379
    params.baseKey = 59
    params.fineTuneCents = 10
    params.ditherOn = true
    var first = SampleDocument(source: source)
    var second = SampleDocument(source: source)
    first.setParams(params)
    second.setParams(params)
    let firstRender = first.processed
    let secondRender = second.processed
    check.expect(
        firstRender.s8 == secondRender.s8 && firstRender.freq == secondRender.freq
            && firstRender.size == secondRender.size && firstRender.loopStart == secondRender.loopStart
            && firstRender.pitchFraction == secondRender.pitchFraction,
        message: "identical source and params render identical bytes and metadata")
    var changed = params
    changed.baseKey = 60
    first.setParams(changed)
    _ = first.processed
    first.setParams(params)
    check.expect(first.processed.s8 == secondRender.s8, message: "reverting params reconstructs identical bytes")
    var middle = SampleDocument(source: source)
    check.expect(middle.processed.seam.valid, message: "mid-loop seam metrics valid")
    check.expect(middle.processed.seam.nccValid, message: "mid-loop seam correlation meaningful")
    var zero = SampleDocument(source: source)
    var fromZero = zero.params
    fromZero.loopStart = 0
    zero.setParams(fromZero)
    check.expect(zero.processed.seam.valid, message: "zero-start loop seam amplitude valid")
    check.expect(!zero.processed.seam.nccValid, message: "zero-start loop seam correlation unavailable")
}

private func renderLoopGeometry(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::parityLoopGeometry")
    guard let source = try? importedHiRes() else {
        check.expect(false, message: "high resolution fixture imports for loop geometry")
        return
    }
    var document = SampleDocument(source: source)
    document.setParams(parityParams(.a, sourceRate: source.sampleRate, params: document.params))
    let sample = document.processed
    check.expect(sample.looped, message: "profile A keeps loop enabled")
    check.expect(sample.loopStart == 607, message: "profile A loop begins at output frame 607")
    check.expect(sample.size == 3034, message: "profile A ends at output frame 3034")
    check.expect(sample.declaredRate == 13379, message: "profile A declared rate is 13379")
}

struct RiffChunk {
    let name: String
    let start: Int
    let size: Int
}

func readRiffChunks(_ bytes: [UInt8]) -> [RiffChunk]? {
    guard bytes.count >= 12, bytes[0..<4].elementsEqual("RIFF".utf8),
        bytes[8..<12].elementsEqual("WAVE".utf8), Int(getU32(bytes, 4)) + 8 == bytes.count
    else { return nil }
    var offset = 12
    var chunks: [RiffChunk] = []
    while offset + 8 <= bytes.count {
        let size = Int(getU32(bytes, offset + 4))
        guard size <= bytes.count - offset - 8, size + (size & 1) <= bytes.count - offset - 8 else { return nil }
        chunks.append(
            RiffChunk(
                name: String(decoding: bytes[offset..<offset + 4], as: UTF8.self),
                start: offset, size: size))
        offset += 8 + size + (size & 1)
    }
    return offset == bytes.count ? chunks : nil
}

private func renderRiffPadding(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::parityRiffPadding")
    guard let source = try? importedHiRes() else {
        check.expect(false, message: "high resolution fixture imports for RIFF padding")
        return
    }
    var document = SampleDocument(source: source)
    document.setParams(parityParams(.f, sourceRate: source.sampleRate, params: document.params))
    let sample = document.processed
    check.expect(sample.size == 7281, message: "profile F produces 7281 odd frames")
    let bytes = Array(SampleWavWriter.bytes(for: sample))
    let chunks = readRiffChunks(bytes)
    check.expect(
        chunks?.first?.name == "fmt " && chunks?.first?.start == 12, message: "fmt chunk starts after RIFF header")
    let data = chunks?.first { $0.name == "data" }
    check.expect(data?.start == 36, message: "data chunk follows 16-byte fmt")
    check.expect(data?.size == 7281, message: "data chunk declares 7281 frames")
    check.expect(
        data.map { bytes[$0.start + 8 + $0.size] == 0 } == true, message: "odd data chunk has zero padding byte")
    check.expect(
        chunks?.map(\.name) == ["fmt ", "data", "smpl", "agbp", "agbl"], message: "smpl follows padded data chunk")
    check.expect(
        chunks?.first { $0.name == "agbp" }.map { $0.start == 36 + 8 + 7281 + 1 + 8 + 36 } == true,
        message: "agbp follows 36-byte unlooped smpl")
    check.expect(
        chunks?.last.map { $0.name == "agbl" && $0.start == bytes.count - 12 } == true,
        message: "agbl follows agbp as final chunk")
}

private func renderRetune(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::retuneVectors")
    var spec = SampleFixtureSpec()
    spec.rate = 44100
    spec.withSmpl = false
    spec.samples = [UInt8](repeating: 128, count: 64)
    guard let source = try? SampleImport.decode(fixtureWav(spec), sourcePath: "f/flat.wav") else {
        check.expect(false, message: "flat WAV fixture imports for retune vectors")
        return
    }
    let vectors: [(Double, Int, Double, UInt32)] = [
        (13379, 60, 0, 13700096), (13379, 72, 0, 6850048),
        (13379, 57, 0, 16292252), (13379, 58, 25, 15157369),
        (3344.75, 60, 0, 3425024), (44100, 69, 50, 26086940), (6689.5, 60, 0, 6850048),
    ]
    var allGolden = true
    for vector in vectors {
        var document = SampleDocument(source: source)
        var params = document.params
        params.targetRate = vector.0
        params.baseKey = vector.1
        params.fineTuneCents = vector.2
        document.setParams(params)
        allGolden = allGolden && document.processed.freq == vector.3
    }
    check.expect(allGolden, message: "all fork retune pitch words match their golden vectors")
}

private func renderCrossfade(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::loopAndCrossfade")
    var spec = SampleFixtureSpec()
    spec.rate = 13379
    spec.bits = 16
    spec.withSmpl = false
    for index in 0..<13379 {
        let value = 0.5 * sin(2 * .pi * 440 * Double(index) / 13379)
        putU16(&spec.samples, UInt16(bitPattern: Int16((value * 32000).rounded())))
    }
    guard let source = try? SampleImport.decode(fixtureWav(spec), sourcePath: "f/cf.wav") else {
        check.expect(false, message: "crossfade fixture imports")
        return
    }
    var params = SampleDocument.defaultParams(for: source)
    params.loopOn = true
    params.loopStart = 4000
    params.loopEnd = 4623
    params.normalizeMode = .off
    params.dcRemove = .off
    params.fadeIn = false
    params.fadeOut = false
    var plain = SampleDocument(source: source)
    plain.setParams(params)
    let original = plain.processed
    check.expect(original.seam.valid && original.seam.ampLsb > 4, message: "mis-seated loop clicks before baking")
    params.crossfadeOn = true
    var baked = SampleDocument(source: source)
    baked.setParams(params)
    let fixed = baked.processed
    var bakedAgain = SampleDocument(source: source)
    bakedAgain.setParams(params)
    check.expect(fixed.s8 == bakedAgain.processed.s8, message: "crossfade bake is deterministic")
    check.expect(
        fixed.seam.valid && fixed.seam.ampLsb < original.seam.ampLsb && fixed.seam.ampLsb <= 3,
        message: "crossfade bake tames the seam click")
    let fadeWindowMatches: Bool =
        fixed.size == original.size
        && fixed.s8.dropLast(160).elementsEqual(original.s8.dropLast(160))
    check.expect(
        fadeWindowMatches,
        message: "crossfade changes only the final fade window")
    params.loopStart = 2
    params.loopEnd = 700
    var tight = SampleDocument(source: source)
    tight.setParams(params)
    check.expect(!tight.processed.warnings.isEmpty, message: "impossible crossfade refuses with a warning")
}

private func renderCompressed(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::compressedContainers")
    guard let path = CheckEnvironment.fixturePath("samplesources/tone.flac"),
        let source = try? SampleImport.decodeFile(path: path)
    else {
        check.expect(false, message: "FLAC source imports for render")
        return
    }
    var document = SampleDocument(source: source)
    let output = document.processed
    check.expect(
        output.size > 0 && output.s8.count == output.size && output.freq > 0,
        message: "FLAC source renders 8-bit playable output")
}

private func renderSoundFont(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::soundFontExtraction")
    guard let file = try? Sf2Reader.read(soundFontFixture().bytes, sourcePath: "f/test.sf2"),
        let source = try? Sf2Reader.extractZone(file, index: 0)
    else {
        report.scoped(cppID: "samplecheck/RenderPipelineSwift::fixture")
            .expect(false, message: "SoundFont zone fixture extracts for render")
        return
    }
    var document = SampleDocument(source: source)
    let sample = document.processed
    check.expect(
        sample.looped && sample.size > sample.loopStart && !sample.s8.isEmpty && sample.freq > 0
            && sample.s8.count == sample.size, message: "SoundFont zone zero renders a looped sample")
}

private func renderCorpus(_ report: CheckReport) {
    guard let root = CheckEnvironment.sampleCorpus else { return }
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::optionalCorpus")
    let directory = URL(fileURLWithPath: root).appendingPathComponent("sound/direct_sound_samples")
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
        report.scoped(cppID: "samplecheck/RenderPipelineSwift::corpus")
            .expect(false, message: "optional corpus directory is readable")
        return
    }
    let wavs = names.filter { $0.hasPrefix("sc88pro_") && $0.hasSuffix(".wav") }.sorted()
    var imported = true, hasHeader = true, freq = true, loopStart = true, size = true
    var loopFlag = true, hasFrames = true, pcm = true
    var peaks: [Double] = []
    var loopRms: [Double] = []
    var compared = 0
    for name in wavs {
        guard let source = try? SampleImport.decodeFile(path: directory.appendingPathComponent(name).path) else {
            imported = false
            continue
        }
        var document = SampleDocument(source: source)
        let sample = document.processed
        let binPath = directory.appendingPathComponent(String(name.dropLast(4)) + ".bin")
        guard let bin = try? Data(contentsOf: binPath), bin.count >= 16 else {
            hasHeader = false
            continue
        }
        let bytes = Array(bin)
        let flags = getU32(bytes, 0)
        freq = freq && sample.freq == getU32(bytes, 4)
        loopStart = loopStart && sample.loopStart == getU32(bytes, 8)
        size = size && sample.size == getU32(bytes, 12)
        loopFlag = loopFlag && sample.looped == (flags & 0x4000_0000 != 0)
        guard sample.size <= bytes.count - 16 else {
            hasFrames = false
            continue
        }
        pcm = pcm && sample.s8.indices.allSatisfy { bytes[16 + $0] == UInt8(bitPattern: sample.s8[$0]) }
        peaks.append(sample.s8.reduce(0) { max($0, abs(Double($1))) })
        if sample.looped && sample.size > sample.loopStart {
            var energy = 0.0
            for index in Int(sample.loopStart)..<Int(sample.size) {
                let value = Double(sample.s8[index])
                energy += value * value
            }
            loopRms.append(sqrt(energy / Double(sample.size - sample.loopStart)))
        }
        compared += 1
    }
    check.expect(!wavs.isEmpty, message: "optional corpus includes SC-88Pro WAV files")
    check.expect(imported && !wavs.isEmpty, message: "optional corpus WAV files all decode")
    check.expect(hasHeader && imported && !wavs.isEmpty, message: "optional corpus binaries have 16-byte headers")
    check.expect(freq && hasHeader, message: "optional corpus frequency words agree")
    check.expect(loopStart && hasHeader, message: "optional corpus loop starts agree")
    check.expect(size && hasHeader, message: "optional corpus frame counts agree")
    check.expect(loopFlag && hasHeader, message: "optional corpus loop flags agree")
    check.expect(hasFrames && hasHeader, message: "optional corpus binaries contain rendered frames")
    check.expect(pcm && hasFrames && hasHeader, message: "optional corpus signed PCM bytes agree")
    check.expect(compared > 0, message: "optional corpus compares a built binary")
    check.expect(!peaks.isEmpty && !loopRms.isEmpty, message: "optional corpus yields peak and loop RMS measurements")
    let peak = peaks.isEmpty ? 0 : median(peaks)
    let rms = loopRms.isEmpty ? 0 : median(loopRms)
    check.expect(peak >= 117 && peak <= 127, message: "optional corpus peak median stays in recorded IQR")
    check.expect(rms >= 37.9 && rms <= 50.7, message: "optional corpus loop RMS median stays in recorded IQR")
}

private func renderZeroCrossing(_ report: CheckReport) {
    let check = report.scoped(cppID: "swiftcore/SampleZeroCrossing::boundedSnap")
    let sine: [Float] = (0..<33).map { (index: Int) -> Float in
        index % 4 == 0 ? 0 : Float(sin(.pi * Double(index) / 4))
    }
    for index in [8, 16, 24, 32] {
        check.expect(
            SampleZeroCrossing.nearest(buffer: sine.span, index: index, windowFrames: 2) == index,
            message: "synthetic sine zero at \(index) is an exact crossing")
    }
    check.expect(
        SampleZeroCrossing.nearest(buffer: sine.span, index: 6, windowFrames: 1) == 5,
        message: "a zero-to-negative sign change closes at the negative frame")
    let tied: [Float] = [1, 1, -1, -1, -1, -1, 1, 1]
    check.expect(
        SampleZeroCrossing.nearest(buffer: tied.span, index: 4, windowFrames: 2) == 2,
        message: "equidistant crossings prefer the lower closing index")
    check.expect(
        SampleZeroCrossing.nearest(buffer: tied.span, index: 4, windowFrames: 1) == 4,
        message: "crossings beyond the search bound leave the index unchanged")
    check.expect(
        SampleZeroCrossing.nearest(buffer: tied.span, index: 4, windowFrames: 0) == 4
            && SampleZeroCrossing.nearest(buffer: tied.span, index: 4, windowFrames: -1) == 4,
        message: "nonpositive windows disable snapping")
    let flat = [Float](repeating: 1, count: 8)
    check.expect(
        SampleZeroCrossing.nearest(buffer: flat.span, index: Int.min, windowFrames: 3) == 0
            && SampleZeroCrossing.nearest(buffer: flat.span, index: Int.max, windowFrames: 3) == 7,
        message: "input indices clamp to the first and last frames")
    let edges: [Float] = [-1, 1, 1, -1]
    check.expect(
        SampleZeroCrossing.nearest(buffer: edges.span, index: -10, windowFrames: 1) == 1
            && SampleZeroCrossing.nearest(buffer: edges.span, index: 10, windowFrames: 1) == 3,
        message: "edge searches use the clamped center and can find boundary crossings")
    check.expect(
        SampleZeroCrossing.nearest(buffer: flat.span, index: 3, windowFrames: Int.max) == 3,
        message: "a crossing-free buffer returns its center even with an unbounded caller window")
    let empty: [Float] = []
    let single: [Float] = [-1]
    check.expect(
        SampleZeroCrossing.nearest(buffer: empty.span, index: 10, windowFrames: 5) == 0
            && SampleZeroCrossing.nearest(buffer: single.span, index: 10, windowFrames: 5) == 0,
        message: "empty and one-frame buffers return the clamped identity index")
    check.expect(
        Int((0.003 * 13379.0).rounded()) == 40 && Int((0.003 * 44100.0).rounded()) == 132,
        message: "caller-computed 3 ms windows are 40 frames at 13379 Hz and 132 at 44100 Hz")
}

private func renderSlice(_ report: CheckReport) {
    let check = report.scoped(cppID: "swiftcore/SampleSlice::renderAndDeclick")
    var buffer = [Float](repeating: 0.5, count: 600)
    for index in 300..<600 { buffer[index] = -0.5 }
    let source = ImportedSample(buffer: buffer, sampleRate: 44100, sourceChannels: 1)
    var params = SampleEditParams()
    params.cropStart = 20
    params.cropEnd = 420
    params.targetRate = 13379
    params.normalizeMode = .oneShot
    params.baseKey = 62
    params.fineTuneCents = 37
    params.ditherOn = true
    let pipeline = SampleRender.render(source: source, params: params)
    let untouched = SampleSlice.render(source: source, params: params, fadeIn: false, fadeOut: false)
    check.expect(
        untouched == pipeline,
        message: "both declick fades off preserve cropped, resampled, normalized, dithered pipeline bytes and metadata")

    params.cropStart = 40
    params.cropEnd = 440
    params.targetRate = source.sampleRate
    params.normalizeMode = .off
    params.fadeIn = false
    params.fadeOut = false
    params.ditherOn = false
    let original = SampleRender.render(source: source, params: params)
    let faded = SampleSlice.render(source: source, params: params)
    let fade = min(Int((0.004 * original.outputRate).rounded()), original.preview.count / 2)
    let tailStart = original.preview.count - fade
    check.expect(
        faded.size == original.size && faded.preview.count == original.preview.count
            && faded.s8.count == original.s8.count,
        message: "default fade-out preserves all output lengths")
    check.expect(
        faded.preview.last == 0 && faded.s8.last == 0,
        message: "fade-out reaches exact float and undithered PCM zero at the last frame")
    let tailWeight = 0.5 * (1 - cos(.pi * Double(fade - 1) / Double(fade)))
    check.expect(
        faded.preview[tailStart] * original.preview[tailStart] > 0
            && faded.preview[tailStart] == Float(Double(original.preview[tailStart]) * tailWeight)
            && abs(faded.preview[tailStart] - original.preview[tailStart]) < 0.0001,
        message: "first affected tail frame keeps its sign and near-original value with the reference half-cosine")
    check.expect(
        faded.preview[..<tailStart].elementsEqual(original.preview[..<tailStart])
            && faded.preview[0] == 0.5,
        message: "default arguments do not fade in or change frames before the tail fade")
    var expected = original.preview
    for index in 0..<fade {
        let weight = 0.5 * (1 - cos(.pi * Double(index) / Double(fade)))
        expected[index] = Float(Double(expected[index]) * weight)
        let position = expected.count - 1 - index
        expected[position] = Float(Double(expected[position]) * weight)
    }
    let combined = SampleSlice.render(source: source, params: params, fadeIn: true, fadeOut: true)
    check.expect(
        fade == 176 && combined.preview == expected
            && combined.preview.first == 0 && combined.preview.last == 0
            && combined.s8 == SampleDsp.quantizeBuffer(expected, dither: false),
        message: "combined mid-length fades mirror the reference shape and bake the quantized slice")
    params.ditherOn = true
    let dithered = SampleSlice.render(source: source, params: params, fadeIn: true, fadeOut: true)
    check.expect(
        dithered.preview == expected && dithered.preview.last == 0
            && dithered.s8 == SampleDsp.quantizeBuffer(expected, dither: true),
        message: "declick preserves exact float zero and uses the existing dither policy without endpoint overrides")

    params.ditherOn = false
    params.cropStart = 0
    params.cropEnd = 101
    let shortOriginal = SampleRender.render(source: source, params: params)
    let short = SampleSlice.render(source: source, params: params)
    let shortFade = min(Int((0.004 * short.outputRate).rounded()), short.preview.count / 2)
    let shortTail = short.preview.count - shortFade
    check.expect(
        Double(short.preview.count) / short.outputRate < 0.008 && shortFade == 50
            && short.preview[..<shortTail].elementsEqual(shortOriginal.preview[..<shortTail])
            && short.preview[shortTail] != shortOriginal.preview[shortTail]
            && short.preview.last == 0,
        message: "a slice shorter than 8 ms fades exactly min(4 ms, half the slice), rounding half down")
    let headOnly = SampleSlice.render(source: source, params: params, fadeIn: true, fadeOut: false)
    check.expect(
        headOnly.preview.first == 0
            && headOnly.preview[shortFade...].elementsEqual(shortOriginal.preview[shortFade...]),
        message: "fade-in alone obeys the same half-slice bound without touching the tail")

    params.cropEnd = 400
    params.targetRate = 13379
    let resampled = SampleRender.render(source: source, params: params)
    let resampledFade = min(Int((0.004 * resampled.outputRate).rounded()), resampled.preview.count / 2)
    let resampledSlice = SampleSlice.render(source: source, params: params)
    let resampledTail = resampled.preview.count - resampledFade
    check.expect(
        resampledSlice.outputRate == 13379 && resampledFade == 54
            && resampledSlice.preview[..<resampledTail].elementsEqual(resampled.preview[..<resampledTail])
            && resampledSlice.preview[resampledTail] != resampled.preview[resampledTail]
            && resampledSlice.preview.last == 0,
        message: "4 ms is measured at the rendered output rate rather than the source rate")

    let silence = ImportedSample(buffer: [Float](repeating: 0, count: 100), sampleRate: 13379)
    params.cropEnd = silence.frameCount
    params.normalizeMode = .auto
    let silent = SampleSlice.render(source: silence, params: params, fadeIn: true, fadeOut: true)
    check.expect(
        silent.preview.count == silence.frameCount
            && silent.preview.allSatisfy { (value: Float) -> Bool in value.isFinite && value == 0 }
            && silent.s8.allSatisfy { (value: Int8) -> Bool in value == 0 },
        message: "a silent region normalizes and declicks without NaN")
    params.cropEnd = 1
    params.normalizeMode = .off
    check.expect(
        SampleSlice.render(source: source, params: params, fadeIn: true, fadeOut: true)
            == SampleRender.render(source: source, params: params),
        message: "a one-frame slice has zero half-slice fade length and remains the pipeline output")
    params.cropEnd = 0
    check.expect(
        SampleSlice.render(source: source, params: params)
            == SampleRender.render(source: source, params: params),
        message: "an empty crop preserves the render's warning and empty output")
}

private func renderRatePolicy(_ report: CheckReport) {
    let check = report.scoped(cppID: "swiftcore/SampleRatePolicy::sharedRates")
    let fixed = [5734, 7884, 10512, 13379, 15768, 18157, 21024, 26758, 31536, 36314, 40137, 42048]
    check.expect(
        SampleRatePolicy.rates == fixed, message: "the fixed table has the 12 existing ascending GBA PCM rates")
    for sourceRate in [8000.0, 13379.0, 44100.0, 48000.5] {
        check.expect(
            SampleRatePolicy.targetRate(gbaReady: true, sourceRate: sourceRate) == sourceRate,
            message: "a GBA-ready source keeps its \(sourceRate) Hz rate")
        check.expect(
            SampleRatePolicy.targetRate(gbaReady: false, sourceRate: sourceRate) == min(sourceRate, 13379),
            message: "a non-GBA-ready source caps at 13379 Hz without upsampling")
    }
    check.expect(
        SampleRatePolicy.rateOptions(sourceRate: 44100) == [44100] + fixed
            && SampleRatePolicy.rateOptions(sourceRate: 48000.5) == [48001] + fixed,
        message: "finite positive source rates round to the first option before the fixed table")
    check.expect(
        SampleRatePolicy.rateOptions(sourceRate: 13379) == [13379] + fixed,
        message: "the source option is not deduplicated against an identical fixed rate")
    for sourceRate in [0.0, -1.0, Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude] {
        check.expect(
            SampleRatePolicy.rateOptions(sourceRate: sourceRate) == fixed,
            message: "invalid or unrepresentable source rate \(sourceRate) omits only the source option")
    }
}
