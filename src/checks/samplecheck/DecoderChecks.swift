import Foundation
import PorydawSample

internal func runDecoderChecks(_ report: CheckReport) {
    decoderWidths(report)
    decoderStereo(report)
    decoderAiff(report)
    decoderRefusals(report)
}

private func decoderWidths(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::decodeWidths")
    do {
        let sample = try SampleImport.decode(preparedSampleWav(), sourcePath: "fix/tone8.wav")
        check.expect(
            sample.sourceKind == .wav && sample.sourcePath == "fix/tone8.wav", message: "prepared u8 WAV imports")
        check.expect(sample.frameCount == 64, message: "u8 prepared frame count")
        let u8SamplesMatch = sample.buffer.indices.allSatisfy { index in
            let expected = Float(Double(index * 2 - 128) / 128)
            return sample.buffer[index] == expected
        }
        check.expect(u8SamplesMatch, message: "u8 samples preserve canonical s8/128 scaling")
        check.expect(
            sample.gbaReady && sample.sourceBits == 8 && sample.sourceChannels == 1,
            message: "u8 prepared shape detected")
        check.expect(
            sample.baseKey == 58 && abs(sample.fracSemitone - 0.25) < 1e-12, message: "u8 smpl unity and fraction")
        check.expect(
            sample.hasLoop && sample.loopStart == 8 && sample.loopEndInclusive == 63 && sample.playLength == 64,
            message: "u8 loop end takes agbl override")
        check.expect(
            sample.exactPitch == 15_000_000 && abs(sample.sampleRate - 13240.0948) < 0.01,
            message: "u8 rate derives from agbp")
        check.expect(sample.suggestedName == "tone8", message: "u8 basename sanitized")
    } catch { check.expect(false, message: "prepared u8 decode failure") }

    var s16 = SampleFixtureSpec()
    s16.bits = 16
    s16.rate = 44100
    s16.withSmpl = false
    for value: Int16 in [0, 16384, -32768, 32767] { putU16(&s16.samples, UInt16(bitPattern: value)) }
    do {
        let sample = try SampleImport.decode(fixtureWav(s16), sourcePath: "f/s16.wav")
        check.expect(sample.sourcePath == "f/s16.wav" && sample.sourceBits == 16, message: "s16 WAV imports")
        check.expect(sample.frameCount == 4, message: "s16 frame count")
        check.expect(sample.buffer[0] == 0, message: "s16 zero conversion")
        check.expect(sample.buffer[1] == 0.5, message: "s16 positive half-scale conversion")
        check.expect(sample.buffer[2] == -1, message: "s16 negative full-scale conversion")
        check.expect(sample.buffer[3] == Float(32767.0 / 32768), message: "s16 positive endpoint conversion")
        check.expect(
            !sample.gbaReady && sample.sampleRate == 44100 && !sample.hasLoop && sample.baseKey == 60,
            message: "s16 hi-res defaults")
    } catch { check.expect(false, message: "s16 valid PCM decode failure") }
    var s24 = SampleFixtureSpec()
    s24.bits = 24
    s24.withSmpl = false
    for value: Int32 in [0, 8_388_607, -8_388_608, -1] {
        let raw = UInt32(bitPattern: value)
        for shift in [0, 8, 16] { s24.samples.append(UInt8(truncatingIfNeeded: raw >> shift)) }
    }
    do {
        let sample = try SampleImport.decode(fixtureWav(s24), sourcePath: "f/s24.wav")
        check.expect(sample.sourcePath == "f/s24.wav" && sample.sourceBits == 24, message: "s24 WAV imports")
        check.expect(sample.frameCount == 4, message: "s24 frame count")
        check.expect(sample.buffer[0] == 0, message: "s24 zero conversion")
        check.expect(sample.buffer[1] == Float(8388607.0 / 8_388_608), message: "s24 positive endpoint conversion")
        check.expect(sample.buffer[2] == -1, message: "s24 negative full-scale conversion")
        check.expect(sample.buffer[3] == Float(-1.0 / 8_388_608), message: "s24 negative unit conversion")
    } catch { check.expect(false, message: "s24 valid PCM decode failure") }
    var f32 = SampleFixtureSpec()
    f32.formatTag = 3
    f32.bits = 32
    f32.withSmpl = false
    for value: Float in [0.5, -0.25, 1.5, -2] { putU32(&f32.samples, value.bitPattern) }
    do {
        let sample = try SampleImport.decode(fixtureWav(f32), sourcePath: "f/f32.wav")
        check.expect(sample.sourcePath == "f/f32.wav" && sample.sourceKind == .wav, message: "f32 WAV imports")
        check.expect(sample.sourceFloat, message: "f32 source identified as float")
        check.expect(sample.frameCount == 4, message: "f32 frame count")
        check.expect(sample.buffer[0] == 0.5, message: "f32 positive half-scale conversion")
        check.expect(sample.buffer[1] == -0.25, message: "f32 negative quarter-scale conversion")
        check.expect(sample.buffer[2] == 1, message: "f32 positive clamping")
        check.expect(sample.buffer[3] == -1, message: "f32 negative clamping")
        check.expect(
            sample.warnings.contains("2 float samples beyond ±1.0 were clamped."), message: "f32 clipping reports count"
        )
    } catch { check.expect(false, message: "f32 valid IEEE float decode failure") }

    var pcm32 = SampleFixtureSpec()
    pcm32.bits = 32
    pcm32.withSmpl = false
    for value: Int32 in [Int32.min, -1, 0, Int32.max] {
        putU32(&pcm32.samples, UInt32(bitPattern: value))
    }
    do {
        let sample = try SampleImport.decode(fixtureWav(pcm32), sourcePath: "sample.pcm32")
        check.expect(
            sample.buffer == [-1, Float(-1.0 / 2_147_483_648), 0, Float(2_147_483_647.0 / 2_147_483_648)],
            message: "PCM32 signed full-scale conversion")
    } catch { check.expect(false, message: "PCM32 decoder refused valid bytes") }

    var extensible = [UInt8](fixtureWav(pcm32))
    extensible.replaceSubrange(16..<20, with: [40, 0, 0, 0])
    extensible.replaceSubrange(20..<22, with: [0xFE, 0xFF])
    // Valid bits, channel mask and PCM subtype GUID follow the ordinary fmt payload.
    extensible.insert(
        contentsOf: [
            22, 0, 32, 0, 1, 0, 0, 0,
            1, 0, 0, 0, 0, 0, 16, 0,
            128, 0, 0, 170, 0, 56, 155, 113,
        ], at: 36)
    let riffSize = UInt32(extensible.count - 8)
    for shift in 0..<4 { extensible[4 + shift] = UInt8(truncatingIfNeeded: riffSize >> (8 * shift)) }
    do {
        let sample = try SampleImport.decode(Data(extensible), sourcePath: "sample.extensible")
        check.expect(
            sample.sourceBits == 32 && sample.buffer[0] == -1 && sample.buffer[3] > 0.99,
            message: "extensible WAV PCM subtype decodes")
    } catch { check.expect(false, message: "extensible PCM WAV refused") }
}

private func decoderStereo(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::decodeStereoPolicy")
    var stereo = SampleFixtureSpec()
    stereo.bits = 16
    stereo.channels = 2
    stereo.withSmpl = false
    let left: [Int16] = (0..<200).map { Int16((16000 * sin(2 * .pi * Double($0) / 50)).rounded()) }
    for value in left {
        putU16(&stereo.samples, UInt16(bitPattern: value))
        putU16(&stereo.samples, UInt16(bitPattern: -value))
    }
    do {
        let data = fixtureWav(stereo)
        let mean = try SampleImport.decode(data, sourcePath: "f/st.wav")
        check.expect(mean.sourcePath == "f/st.wav" && mean.sourceChannels == 2, message: "anti-phase stereo imports")
        check.expect(mean.frameCount == 200, message: "anti-phase stereo frame count")
        check.expect(mean.buffer.allSatisfy { abs($0) < 1e-6 }, message: "anti-phase mean cancels")
        check.expect(mean.phaseCancelStereo && mean.sourceChannels == 2, message: "negative stereo correlation flagged")
        check.expect(
            mean.warnings.contains { $0.contains("phase-cancelling") }, message: "phase cancellation warning emitted")
        let selected = try SampleImport.decode(data, sourcePath: "f/st.wav", leftChannelOnly: true)
        check.expect(
            selected.sourcePath == "f/st.wav" && selected.sourceChannels == 2, message: "left-only re-import works")
        check.expect(selected.frameCount == 200, message: "left-only frame count")
        check.expect(
            selected.buffer == left.map { Float($0) / 32768 }, message: "left-only takes channel zero verbatim")
        check.expect(
            !selected.phaseCancelStereo && selected.warnings.contains("imported the left channel only."),
            message: "left-only warning and provenance")
    } catch { check.expect(false, message: "anti-phase stereo decode failure") }
    stereo.samples.removeAll()
    for value in left {
        putU16(&stereo.samples, UInt16(bitPattern: value))
        putU16(&stereo.samples, UInt16(bitPattern: value / 2))
    }
    do {
        let mean = try SampleImport.decode(fixtureWav(stereo), sourcePath: "f/stm.wav")
        check.expect(mean.sourcePath == "f/stm.wav" && mean.frameCount == 200, message: "in-phase stereo imports")
        check.expect(!mean.phaseCancelStereo, message: "in-phase stereo does not cancel")
        check.expect(
            mean.buffer[12] == Float((Double(left[12]) + Double(left[12] / 2)) / 2 / 32768),
            message: "stereo mean retains double precision")
    } catch { check.expect(false, message: "in-phase stereo decode failure") }
    var precise = SampleFixtureSpec()
    precise.formatTag = 3
    precise.bits = 64
    precise.channels = 2
    precise.withSmpl = false
    let residual: Double = 1.0 / 1_073_741_824
    for value in [0.5 + residual, -0.5 + residual, 0.125, 1.5] {
        putU32(&precise.samples, UInt32(truncatingIfNeeded: value.bitPattern))
        putU32(&precise.samples, UInt32(truncatingIfNeeded: value.bitPattern >> 32))
    }
    do {
        let data = fixtureWav(precise)
        let mean = try SampleImport.decode(data, sourcePath: "f/precise.wav")
        check.expect(mean.sourcePath == "f/precise.wav" && mean.sourceBits == 64, message: "f64 stereo mean imports")
        check.expect(mean.buffer == [Float(residual), 0.5625], message: "f64 mean preserves sub-float precision")
        let selected = try SampleImport.decode(data, sourcePath: "f/precise.wav", leftChannelOnly: true)
        check.expect(
            selected.sourcePath == "f/precise.wav" && selected.sourceBits == 64, message: "f64 left-only imports")
        check.expect(selected.buffer == [0.5, 0.125], message: "f64 left-only keeps channel zero")
        check.expect(selected.warnings.count == 2, message: "ignored right channel still reports clipping")
    } catch { check.expect(false, message: "f64 stereo imports") }
}

private func decoderAiff(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::decodeAiff")
    var spec = AiffFixtureSpec()
    spec.numFrames = 500
    spec.rate = 22050
    spec.baseNote = 57
    spec.detune = -25
    spec.loop = true
    spec.loopStartPos = 100
    spec.loopEndPos = 400
    let values: [Int16] = (0..<500).map { Int16(($0 * 37) % 30001 - 15000) }
    for value in values { putBe16(&spec.ssnd, UInt16(bitPattern: value)) }
    do {
        let sample = try SampleImport.decode(fixtureAiff(spec), sourcePath: "f/a.aif")
        check.expect(sample.sourcePath == "f/a.aif" && sample.sourceChannels == 1, message: "AIFF source imports")
        check.expect(sample.frameCount == 500, message: "AIFF frame count")
        check.expect(sample.buffer == values.map { Float($0) / 32768 }, message: "AIFF signed BE PCM conversion")
        check.expect(sample.sampleRate == 22050 && sample.sourceKind == .aif, message: "AIFF extended-80 rate")
        check.expect(
            sample.hasLoop && sample.loopStart == 100 && sample.loopEndInclusive == 399,
            message: "AIFF MARK INST exclusive-end loop")
        check.expect(
            sample.baseKey == 56 && abs(sample.fracSemitone - 0.75) < 1e-12, message: "AIFF detune renormalized")
    } catch { check.expect(false, message: "AIFF source decode failure") }

    for bits: UInt16 in [8, 24, 32] {
        var aiff = AiffFixtureSpec()
        aiff.sampleSize = bits
        aiff.numFrames = 2
        switch bits {
        case 8: aiff.ssnd = [0x80, 0x40]
        case 24: aiff.ssnd = [0x80, 0, 0, 0x40, 0, 0]
        default: aiff.ssnd = [0x80, 0, 0, 0, 0x40, 0, 0, 0]
        }
        do {
            let sample = try SampleImport.decode(fixtureAiff(aiff), sourcePath: "test.aiff")
            check.expect(
                sample.frameCount == 2 && sample.buffer == [-1, 0.5],
                message: "AIFF \(bits)-bit BE signed PCM conversion")
        } catch { check.expect(false, message: "AIFF \(bits)-bit valid input refused") }
    }
}

private func decoderRefusals(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::decodeRefusalBoundaries")
    var lying = SampleFixtureSpec()
    lying.bits = 16
    lying.withSmpl = false
    for index in 0..<32 { putU16(&lying.samples, UInt16(index)) }
    var bytes = fixtureWav(lying)
    bytes.replaceSubrange(40..<44, with: [0xF0, 0xFF, 0xFF, 0x7F])
    do {
        let sample = try SampleImport.decode(bytes, sourcePath: "f/lying.wav")
        check.expect(sample.sourcePath == "f/lying.wav", message: "lying WAV chunk accepted")
        check.expect(sample.frameCount == 32, message: "lying WAV data size clamps to present frames")
        check.expect(sample.buffer[1] == 1 / 32768, message: "lying WAV second sample preserved")
        if let root = CheckEnvironment.fixtureRoot {
            let url = URL(fileURLWithPath: root).appendingPathComponent("samplecheck-240-ingress.wav")
            do {
                try bytes.write(to: url)
                defer { try? FileManager.default.removeItem(at: url) }
                let loaded = try SampleImport.decodeFile(path: url.path)
                check.expect(
                    loaded.buffer == sample.buffer && loaded.sourcePath == url.path,
                    message: "WAV file ingress preserves decoded frames")
            } catch { check.expect(false, message: "WAV file ingress reads scratch fixture") }
        } else {
            check.expect(false, message: "samplecheck scratch root exists")
        }
    } catch { check.expect(false, message: "lying WAV data chunk imports") }
    do {
        _ = try SampleImport.decode(Data("MThd not audio at all".utf8), sourcePath: "f/x.mid")
        check.expect(false, message: "unsupported source refused")
    } catch {
        check.expect(
            error.message == "not a supported audio file (WAV, AIFF, MP3, FLAC, and Ogg Vorbis sources are supported).",
            message: "unsupported source has actionable refusal")
        check.expect(!error.message.isEmpty, message: "rejected garbage reports a refusal")
    }
    var aifc = fixtureAiff(AiffFixtureSpec())
    aifc.replaceSubrange(8..<12, with: Array("AIFC".utf8))
    do {
        _ = try SampleImport.decode(aifc, sourcePath: "f/x.aifc")
        check.expect(false, message: "AIFF-C refused")
    } catch {
        check.expect(
            error.message == "AIFF-C is not supported — export uncompressed AIFF or WAV.",
            message: "AIFF-C refusal text")
        check.expect(!error.message.isEmpty, message: "rejected AIFF-C reports a refusal")
    }
    do {
        _ = try SampleImport.decodeFile(path: "/nonexistent/porydaw-samplecheck-240.wav")
        check.expect(false, message: "unreadable sample path refuses")
    } catch {
        check.expect(
            error.message == "cannot read /nonexistent/porydaw-samplecheck-240.wav.",
            message: "unreadable sample path reports source path")
    }

    var looping = SampleFixtureSpec()
    looping.samples = [UInt8](repeating: 128, count: 16)
    looping.numLoops = 1
    looping.loopStart = 3
    looping.loopEndInclusive = 12
    looping.loopType = 1
    do {
        let sample = try SampleImport.decode(fixtureWav(looping), sourcePath: "bad-loop.wav")
        check.expect(
            !sample.hasLoop && sample.warnings.contains("the smpl loop is not a forward loop — ignored."),
            message: "non-forward WAV loop reports refusal of loop only")
    } catch { check.expect(false, message: "valid WAV with non-forward loop refused") }

    var soundFont = Data("RIFF".utf8) + Data(repeating: 0, count: 4) + Data("sfbk".utf8)
    do {
        _ = try SampleImport.decode(soundFont, sourcePath: "wrong.wav")
        check.expect(false, message: "SoundFont single-stream ingress refused")
    } catch {
        check.expect(
            error.message == "SoundFont files hold multiple samples — pick a zone with the SoundFont zone picker.",
            message: "SoundFont routes to zone picker")
    }
    soundFont[8] = UInt8(ascii: "W")
    soundFont[9] = UInt8(ascii: "A")
    soundFont[10] = UInt8(ascii: "V")
    soundFont[11] = UInt8(ascii: "E")
    do {
        _ = try SampleImport.decode(soundFont, sourcePath: "broken.wav")
        check.expect(false, message: "truncated WAV refused")
    } catch {
        check.expect(
            error.message == "the WAV file is corrupt or truncated.", message: "truncated WAV reports corruption")
    }
}
