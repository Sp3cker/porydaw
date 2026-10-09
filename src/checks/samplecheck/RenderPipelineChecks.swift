import Foundation
import PorydawSample

public func runRenderPipelineChecks(_ report: CheckReport) {
    renderDeterminism(report)
    renderLoopGeometry(report)
    renderRiffPadding(report)
    renderRetune(report)
    renderCrossfade(report)
    renderCompressed(report)
    renderSoundFont(report)
    renderCorpus(report)
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
