import Foundation
import PorydawSample

internal func runCompressedDecoderChecks(_ report: CheckReport) {
    compressedContainers(report)
    compressedRefusals(report)
}

private func compressedContainers(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::compressedContainers")
    guard let root = CheckEnvironment.fixtureRoot else {
        check.expect(false, message: "compressed fixture root is staged")
        return
    }
    let source = URL(fileURLWithPath: root).appendingPathComponent("samplesources")
    do {
        let mp3 = try SampleImport.decodeFile(path: source.appendingPathComponent("tone.mp3").path)
        check.expect(mp3.sourceKind == .mp3 && mp3.sourcePath.hasSuffix("tone.mp3"), message: "mp3 fixture decodes")
        check.expect(
            mp3.sourceChannels == 1 && mp3.sourceBits == 0 && !mp3.hasPitchMetadata && !mp3.hasLoop
                && !mp3.gbaReady && mp3.sampleRate == 22050 && mp3.playLength == mp3.frameCount,
            message: "mp3 structure and metadata defaults")
        check.expect(mp3.frameCount == 5512, message: "mp3 gapless frame count")
        if mp3.frameCount == 5512 {
            let amp = toneAmp(mp3.buffer, 22050, 440, 1024, mp3.frameCount - 1024)
            check.expect(abs(amp - 0.5) < 0.05, message: "mp3 tone amplitude near 0.5")
        }
    } catch { check.expect(false, message: "mp3 fixture decoding failure") }

    do {
        let flac = try SampleImport.decodeFile(path: source.appendingPathComponent("tone.flac").path)
        check.expect(
            flac.sourceKind == .flac && flac.sourcePath.hasSuffix("tone.flac"), message: "flac fixture decodes")
        check.expect(
            flac.sourceChannels == 1 && flac.sourceBits == 24 && !flac.hasPitchMetadata && !flac.hasLoop
                && flac.sampleRate == 22050,
            message: "flac structure and metadata defaults")
        check.expect(flac.frameCount == 5512, message: "flac frame count")
        if flac.frameCount == 5512 {
            let reference = genSine(22050, 440, 0.25, 0.5)
            var maxDiff = 0.0
            for index in reference.indices {
                maxDiff = max(maxDiff, abs(Double(flac.buffer[index]) - Double(reference[index])))
            }
            check.expect(maxDiff < 3e-7, message: "flac decode matches the source sine")
            var hash: UInt64 = 1_469_598_103_934_665_603
            for value in flac.buffer {
                let bits = value.bitPattern
                for shift in stride(from: 0, to: 32, by: 8) {
                    hash = (hash ^ UInt64((bits >> shift) & 0xFF)) &* 1_099_511_628_211
                }
            }
            check.expect(hash == 0x6c3d_0541_41a6_aae7, message: "flac bit-exact PCM golden hash")
        }
    } catch { check.expect(false, message: "flac fixture decoding failure") }

    do {
        let ogg = try SampleImport.decodeFile(path: source.appendingPathComponent("tone.ogg").path)
        check.expect(ogg.sourceKind == .ogg && ogg.sourcePath.hasSuffix("tone.ogg"), message: "ogg fixture decodes")
        check.expect(
            ogg.sourceChannels == 2 && ogg.sourceBits == 0 && !ogg.hasPitchMetadata && !ogg.hasLoop
                && !ogg.phaseCancelStereo && ogg.sampleRate == 22050,
            message: "ogg structure and metadata defaults")
        check.expect(ogg.frameCount == 5512, message: "ogg frame count")
        if ogg.frameCount == 5512 {
            let amp = toneAmp(ogg.buffer, 22050, 440, 512, ogg.frameCount - 512)
            check.expect(abs(amp - 0.45) < 0.05, message: "ogg stereo mean-downmix amplitude near 0.45")
        }
        let left = try SampleImport.decodeFile(
            path: source.appendingPathComponent("tone.ogg").path, leftChannelOnly: true)
        check.expect(
            left.sourceChannels == 2 && left.warnings.contains("imported the left channel only."),
            message: "ogg left-only re-import decodes with the warning")
        if left.frameCount == 5512 {
            let amp = toneAmp(left.buffer, 22050, 440, 512, left.frameCount - 512)
            check.expect(abs(amp - 0.5) < 0.05, message: "ogg left-only amplitude near 0.5")
        }
    } catch { check.expect(false, message: "ogg fixture decoding failure") }
}

private func compressedRefusals(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::compressedRefusals")
    guard let root = CheckEnvironment.fixtureRoot else {
        check.expect(false, message: "compressed refusal fixture root is staged")
        return
    }
    let source = URL(fileURLWithPath: root).appendingPathComponent("samplesources")
    do {
        _ = try SampleImport.decodeFile(path: source.appendingPathComponent("tone.opus").path)
        check.expect(false, message: "unexpected Opus import")
    } catch {
        check.expect(
            error.message
                == "cannot decode the Ogg file — only Ogg Vorbis is supported (Opus and other codecs are not).",
            message: "ogg opus refuses")
        check.expect(!error.message.isEmpty, message: "refused codec reports an error")
    }
    guard let mp3 = try? Data(contentsOf: source.appendingPathComponent("tone.mp3")),
        let flac = try? Data(contentsOf: source.appendingPathComponent("tone.flac"))
    else {
        check.expect(false, message: "compressed refusal seed files are staged")
        return
    }
    var badMp3 = Data("ID3\u{04}".utf8)
    badMp3.append(contentsOf: repeatElement(UInt8(0), count: 6))
    badMp3.append(contentsOf: mp3.prefix(64).map { _ in UInt8(0) })
    do {
        _ = try SampleImport.decode(badMp3, sourcePath: "f/bad.mp3")
        check.expect(false, message: "unexpected sync-less MP3 import")
    } catch {
        check.expect(error.message == "the MP3 file is corrupt or truncated.", message: "sync-less mp3 refuses")
        check.expect(!error.message.isEmpty, message: "refused MP3 stream reports an error")
    }
    var badFlac = Data("fLaC".utf8)
    badFlac.append(contentsOf: flac.prefix(64).map { _ in UInt8(ascii: "x") })
    do {
        _ = try SampleImport.decode(badFlac, sourcePath: "f/bad.flac")
        check.expect(false, message: "unexpected corrupt FLAC import")
    } catch {
        check.expect(error.message == "the FLAC file is corrupt or truncated.", message: "corrupt flac refuses")
        check.expect(!error.message.isEmpty, message: "refused FLAC stream reports an error")
    }
}
