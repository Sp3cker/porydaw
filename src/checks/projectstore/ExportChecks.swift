import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawCore
import PorydawDocument

private enum ExportCheckError: Error {
    case failed(String)
}

private let exportRate = 44_100
private let exportOptions = WavExportOptions(
    sampleRate: exportRate, loopCount: 1,
    fadeoutSeconds: 1, tailSeconds: 1)

private struct ExportFixture {
    let song: LoadedSong
    let timeline: PlaybackTimeline
    let scratch: URL
    let settings: AudioSettings

    // Independent oracle: original tst_midiexport.cpp expectedTotalSamples.
    var expectedTotalFrames: UInt64 {
        if timeline.hasLoop {
            return timeline.loopStartSample + (timeline.loopEndSample - timeline.loopStartSample) + UInt64(exportRate)
        }
        return timeline.lengthSamples + UInt64(exportRate)
    }
}

private func exportRequire(_ condition: Bool, _ reason: String) throws {
    guard condition else { throw ExportCheckError.failed(reason) }
}

@MainActor
private func withExportFixture(
    label: String, report: CheckReport,
    _ body: (ExportFixture) throws -> Void
) throws {
    var isDirectory: ObjCBool = false
    guard let root = CheckEnvironment.fixtureRoot,
        FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
        isDirectory.boolValue
    else {
        throw ExportCheckError.failed(
            "exportcheck project root is not a directory: \(CheckEnvironment.fixtureRoot ?? "")")
    }
    guard !label.isEmpty else {
        throw ExportCheckError.failed("exportcheck requires a song label")
    }
    let service = ProjectService()
    let outcome = Result {
        try runBlocking { try await service.open(root: root) }
        let song = try runBlocking { try await service.openSong(label: label) }
        let file = try MidiFile.decode(song.midiBytes)
        let timeline = PlaybackTimeline.build(
            file: file, sampleRate: Double(exportRate),
            settings: PlaybackSettings(
                exactGate: song.config.exactGate,
                extendedClocks: song.config.extendedClocks))
        report.expect(
            song.label == label && timeline.sampleRate == Double(exportRate),
            cppID: "exportcheck/MidiExportTest::\(label)",
            message: "S003: staged song opens and builds its export timeline")
        var settings = AudioSettings()
        settings.songVolume = UInt8(clamping: song.config.masterVolume)
        settings.reverb = UInt8(clamping: max(0, song.config.reverb ?? 0))
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("exportcheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        report.expect(
            FileManager.default.fileExists(atPath: scratch.path),
            cppID: "exportcheck/MidiExportTest::\(label)",
            message: "S006: per-case WAV export scratch directory is created")
        try body(ExportFixture(song: song, timeline: timeline, scratch: scratch, settings: settings))
    }
    try runBlocking { await service.close() }
    try outcome.get()
}

private func le16(_ bytes: Data, _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
}

private func le32(_ bytes: Data, _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3])
        << 24
}

private func correlation(_ baseline: Data, _ suppressed: Data, lag: Int) -> Double {
    let frames = (min(baseline.count, suppressed.count) - 44) / 4
    guard frames > lag else { return 0 }
    var dot = 0.0
    var baselinePower = 0.0
    var suppressedPower = 0.0
    for frame in 0..<(frames - lag) {
        for channel in 0..<2 {
            let a = Double(Int16(bitPattern: le16(baseline, 44 + frame * 4 + channel * 2)))
            let b = Double(Int16(bitPattern: le16(suppressed, 44 + (frame + lag) * 4 + channel * 2)))
            dot += a * b
            baselinePower += a * a
            suppressedPower += b * b
        }
    }
    guard baselinePower > 0 && suppressedPower > 0 else { return 0 }
    return dot / (sqrt(baselinePower) * sqrt(suppressedPower))
}

@MainActor
private func exportCase(
    _ name: String, labels: [String], _ report: CheckReport,
    _ body: (ExportFixture) throws -> Void
) {
    for label in labels {
        let cppID = "exportcheck/MidiExportTest::\(name)"
        do {
            try withExportFixture(label: label, report: report, body)
        } catch {
            report.fail(cppID, "\(name)[\(label)]: \(error)")
        }
    }
}

@MainActor
public func runExportChecks(_ report: CheckReport) {
    let labels = ["mus_route101", "mus_route102"].filter {
        CheckEnvironment.fixturePath("sound/songs/midi/\($0).mid")
            .map { FileManager.default.fileExists(atPath: $0) } == true
    }
    let stagedLabels = labels.isEmpty ? [""] : labels

    exportCase("durationCalculationMatchesRenderParity", labels: stagedLabels, report) { fixture in
        let totals = WavExportTotals(timeline: fixture.timeline, options: exportOptions)
        report.expect(
            totals.totalFrames == fixture.expectedTotalFrames,
            cppID: "exportcheck/MidiExportTest::durationCalculationMatchesRenderParity",
            message: "S004: production totals equal independent expected frame count")
        let path = fixture.scratch.appendingPathComponent("parity.wav")
        let result = try WavExport.render(
            to: path.path, timeline: fixture.timeline, voices: fixture.song.bank.engineVoices,
            settings: fixture.settings, options: exportOptions, progress: { _ in true })
        try exportRequire(result == .completed, "duration render was cancelled")
        let bytes = try Data(contentsOf: path)
        report.expect(
            bytes.count == 44 + Int(fixture.expectedTotalFrames) * 4,
            cppID: "exportcheck/MidiExportTest::durationCalculationMatchesRenderParity",
            message: "duration render frame count matches independent expected total")
    }

    exportCase("offlineExportProducesValidRiffPcm", labels: stagedLabels, report) { fixture in
        let totals = WavExportTotals(timeline: fixture.timeline, options: exportOptions)
        let path = fixture.scratch.appendingPathComponent("export.wav")
        var previous = -1.0
        var monotonic = true
        let result = try WavExport.render(
            to: path.path, timeline: fixture.timeline, voices: fixture.song.bank.engineVoices,
            settings: fixture.settings, options: exportOptions
        ) { fraction in
            monotonic = monotonic && fraction > previous
            previous = fraction
            return true
        }
        report.expect(
            result == .completed,
            cppID: "exportcheck/MidiExportTest::offlineExportProducesValidRiffPcm",
            message: "S007: WAV export completes")
        report.expect(
            monotonic && previous == 1.0,
            cppID: "exportcheck/MidiExportTest::offlineExportProducesValidRiffPcm",
            message: "S008: progress strictly increases and ends at one")
        let wav = try Data(contentsOf: path)
        report.expect(
            wav.count == 44 + Int(totals.totalFrames) * 4,
            cppID: "exportcheck/MidiExportTest::offlineExportProducesValidRiffPcm",
            message: "S010: WAV byte count equals header plus stereo frames")
        guard wav.count >= 44 else { throw ExportCheckError.failed("WAV header truncated") }
        report.expect(
            String(decoding: wav[0..<4], as: UTF8.self) == "RIFF" && le32(wav, 4) == UInt32(wav.count - 8)
                && String(decoding: wav[8..<12], as: UTF8.self) == "WAVE"
                && String(decoding: wav[12..<16], as: UTF8.self) == "fmt " && le32(wav, 16) == 16 && le16(wav, 20) == 1
                && le16(wav, 22) == 2 && le32(wav, 24) == UInt32(exportRate)
                && le32(wav, 28) == UInt32(exportRate * 4) && le16(wav, 32) == 4 && le16(wav, 34) == 16
                && String(decoding: wav[36..<40], as: UTF8.self) == "data"
                && le32(wav, 40) == UInt32(totals.totalFrames * 4),
            cppID: "exportcheck/MidiExportTest::offlineExportProducesValidRiffPcm",
            message: "S011: RIFF stereo PCM header fields match expected values")
        var peak = 0
        var tailPeak = 0
        for offset in stride(from: 44, to: wav.count - 1, by: 2) {
            let magnitude = abs(Int(Int16(bitPattern: le16(wav, offset))))
            peak = max(peak, magnitude)
            if fixture.timeline.hasLoop && offset >= wav.count - 16 * 4 { tailPeak = max(tailPeak, magnitude) }
        }
        report.expect(
            peak >= 256,
            cppID: "exportcheck/MidiExportTest::offlineExportProducesValidRiffPcm",
            message: "S012: exported PCM has an audible peak")
        if fixture.timeline.hasLoop {
            report.expect(
                totals.totalFrames >= 16,
                cppID: "exportcheck/MidiExportTest::offlineExportProducesValidRiffPcm",
                message: "S013: loop has at least sixteen fade frames")
            report.expect(
                tailPeak <= peak / 16,
                cppID: "exportcheck/MidiExportTest::offlineExportProducesValidRiffPcm",
                message: "S014: final sixteen loop frames fade beneath peak")
        }
    }

    exportCase("zeroFadeLoopPreservesPcm", labels: stagedLabels, report) { fixture in
        guard fixture.timeline.hasLoop else { return }
        var options = exportOptions
        options.fadeoutSeconds = 0
        let totals = WavExportTotals(timeline: fixture.timeline, options: options)
        let path = fixture.scratch.appendingPathComponent("zero-fade.wav")
        let result = try WavExport.render(
            to: path.path, timeline: fixture.timeline, voices: fixture.song.bank.engineVoices,
            settings: fixture.settings, options: options, progress: { _ in true })
        let bytes = try Data(contentsOf: path)
        let peak =
            stride(from: 44, to: bytes.count - 1, by: 2)
            .map { abs(Int(Int16(bitPattern: le16(bytes, $0)))) }.max() ?? 0
        report.expect(
            result == .completed && totals.totalFrames == totals.fadeStartFrame
                && bytes.count == 44 + Int(totals.totalFrames) * 4 && peak >= 256,
            cppID: "exportcheck/WavExport::zeroFadeLoop",
            message: "zero-fade loop exports non-silent full-length PCM")
    }

    exportCase("resonanceSuppressionChangesPcmWithoutChangingFrames", labels: stagedLabels, report) { fixture in
        let baselinePath = fixture.scratch.appendingPathComponent("baseline.wav")
        let suppressedPath = fixture.scratch.appendingPathComponent("suppressed.wav")
        let baseline = try WavExport.render(
            to: baselinePath.path, timeline: fixture.timeline, voices: fixture.song.bank.engineVoices,
            settings: fixture.settings, options: exportOptions, progress: { _ in true })
        report.expect(
            baseline == .completed,
            cppID: "exportcheck/MidiExportTest::resonanceSuppressionChangesPcmWithoutChangingFrames",
            message: "S015: baseline export completes")
        let before = try Data(contentsOf: baselinePath)
        report.expect(
            before.count >= 44,
            cppID: "exportcheck/MidiExportTest::resonanceSuppressionChangesPcmWithoutChangingFrames",
            message: "S017: baseline WAV reads back with a complete header")
        var suppressedOptions = exportOptions
        suppressedOptions.resonanceSuppression = true
        let suppressed = try WavExport.render(
            to: suppressedPath.path, timeline: fixture.timeline, voices: fixture.song.bank.engineVoices,
            settings: fixture.settings, options: suppressedOptions, progress: { _ in true })
        report.expect(
            suppressed == .completed,
            cppID: "exportcheck/MidiExportTest::resonanceSuppressionChangesPcmWithoutChangingFrames",
            message: "S016: suppressed export completes")
        let after = try Data(contentsOf: suppressedPath)
        report.expect(
            after.count >= 44,
            cppID: "exportcheck/MidiExportTest::resonanceSuppressionChangesPcmWithoutChangingFrames",
            message: "S018: suppressed WAV reads back with a complete header")
        report.expect(
            after.count == before.count,
            cppID: "exportcheck/MidiExportTest::resonanceSuppressionChangesPcmWithoutChangingFrames",
            message: "S019: suppression retains the frame count")
        report.expect(
            before.count >= 44 && after.count >= 44 && before.dropFirst(44) != after.dropFirst(44),
            cppID: "exportcheck/MidiExportTest::resonanceSuppressionChangesPcmWithoutChangingFrames",
            message: "S020: suppressed PCM differs from baseline")
        report.expect(
            correlation(before, after, lag: 0) >= 0.9
                && correlation(before, after, lag: 0) > correlation(before, after, lag: 2047),
            cppID: "exportcheck/WavExport::suppressionAlignment",
            message: "suppression is aligned without a 2047-frame delay")
    }

    exportCase("cancelledExportRemovesPartialFile", labels: stagedLabels, report) { fixture in
        let path = fixture.scratch.appendingPathComponent("cancelled.wav")
        var firstFraction = -1.0
        let result = try WavExport.render(
            to: path.path, timeline: fixture.timeline, voices: fixture.song.bank.engineVoices,
            settings: fixture.settings, options: exportOptions
        ) { fraction in
            firstFraction = fraction
            return false
        }
        report.expect(
            firstFraction == 0 && result == .cancelled,
            cppID: "exportcheck/MidiExportTest::cancelledExportRemovesPartialFile",
            message: "S021: progress-zero cancellation returns cancelled")
        report.expect(
            !FileManager.default.fileExists(atPath: path.path),
            cppID: "exportcheck/MidiExportTest::cancelledExportRemovesPartialFile",
            message: "S022: cancelled export removes its partial file")
    }

    let id = "exportcheck/WavExport"
    exportCase("totalsAndPreview", labels: stagedLabels, report) { fixture in
        let own = WavExportTotals(timeline: fixture.timeline, options: exportOptions)
        report.expect(
            WavExportTotals.previewSeconds(timeline: fixture.timeline, options: exportOptions)
                == Int(Double(own.totalFrames) / Double(exportRate) + 0.5)
                && WavExportTotals.clockText(seconds: 125) == "2:05"
                && WavExportTotals.clockText(seconds: 59) == "0:59",
            cppID: "\(id)::preview", message: "preview rounds duration and formats m:ss")
        if fixture.timeline.hasLoop {
            var three = exportOptions
            three.loopCount = 3
            var two = exportOptions
            two.loopCount = 2
            report.expect(
                WavExportTotals(timeline: fixture.timeline, options: three).totalFrames
                    - WavExportTotals(timeline: fixture.timeline, options: two).totalFrames == fixture.timeline
                    .loopEndSample - fixture.timeline.loopStartSample,
                cppID: "\(id)::loopCount", message: "three loops minus two adds one loop")
            let fade = WavExportTotals(timeline: fixture.timeline, options: exportOptions)
            let length = fade.totalFrames - fade.fadeStartFrame
            report.expect(
                length > 0 && fade.gain(atFrame: fade.fadeStartFrame - 1) == 1
                    && fade.gain(atFrame: fade.fadeStartFrame) == 1
                    && abs(fade.gain(atFrame: fade.totalFrames - 1) - 1 / Float(length)) < 0.000001,
                cppID: "\(id)::fadeGain", message: "fade preserves first and terminal gain")
        } else {
            let plain = WavExportTotals(timeline: fixture.timeline, options: exportOptions)
            report.expect(
                plain.gain(atFrame: 0) == 1 && plain.gain(atFrame: plain.totalFrames - 1) == 1,
                cppID: "\(id)::noLoopGain", message: "nonloop output never fades")
        }
        var zero = exportOptions
        zero.fadeoutSeconds = 0
        zero.tailSeconds = 0
        let zeroTotals = WavExportTotals(timeline: fixture.timeline, options: zero)
        report.expect(
            fixture.timeline.hasLoop
                ? zeroTotals.totalFrames == zeroTotals.fadeStartFrame
                : zeroTotals.totalFrames == fixture.timeline.lengthSamples,
            cppID: "\(id)::zeroDurations", message: "zero duration yields no additional output")
        var fractional = exportOptions
        fractional.fadeoutSeconds = 0.1
        fractional.tailSeconds = 0.1
        let small = WavExportTotals(timeline: fixture.timeline, options: fractional)
        report.expect(
            small.totalFrames - zeroTotals.totalFrames == 4_410,
            cppID: "\(id)::rounding", message: "tenths of seconds round to 4410 frames at 44100 Hz")
        fractional.sampleRate = 32_000
        fractional.fadeoutSeconds = 1.25
        fractional.tailSeconds = 1.25
        let large = WavExportTotals(timeline: fixture.timeline, options: fractional)
        let zeroAt32k = WavExportTotals(
            timeline: fixture.timeline,
            options: WavExportOptions(
                sampleRate: 32_000, loopCount: 1,
                fadeoutSeconds: 0, tailSeconds: 0))
        report.expect(
            large.totalFrames - zeroAt32k.totalFrames == 40_000,
            cppID: "\(id)::rounding", message: "one and a quarter seconds round to 40000 frames at 32000 Hz")
        let missing = fixture.scratch.appendingPathComponent("missing/output.wav")
        do {
            _ = try WavExport.render(
                to: missing.path, timeline: fixture.timeline, voices: fixture.song.bank.engineVoices,
                settings: fixture.settings, options: exportOptions, progress: { _ in true })
            report.expect(false, cppID: "\(id)::openFailure", message: "missing directory must refuse export")
        } catch let error as WavExportError {
            report.expect(
                error.message.hasPrefix("Cannot write \(missing.path): ")
                    && !FileManager.default.fileExists(atPath: missing.path),
                cppID: "\(id)::openFailure", message: "open failure names path and leaves no output")
        }
    }
    do {
        let accepted = try WavExport.header(
            totals: .init(totalFrames: 1_073_741_814, fadeStartFrame: .max),
            sampleRate: exportRate)
        report.expect(
            le32(Data(accepted), 40) == 4_294_967_256,
            cppID: "\(id)::riffBoundary", message: "largest legal RIFF payload is accepted")
    } catch { report.fail("\(id)::riffBoundary", "boundary header rejected: \(error)") }
    let refusals: [(UInt64, WavExportError, String)] = [
        (0, .nothingToRender, "Nothing to render."),
        (
            1_073_741_815, .exceedsRiffLimit,
            "The rendered file would exceed the 4 GB WAV limit — reduce the loop count."
        ),
    ]
    for (frames, expected, text) in refusals {
        do {
            _ = try WavExport.header(
                totals: .init(totalFrames: frames, fadeStartFrame: .max),
                sampleRate: exportRate)
            report.expect(false, cppID: "\(id)::riffRefusals", message: "invalid RIFF size must refuse")
        } catch {
            report.expect(
                error == expected && error.message == text,
                cppID: "\(id)::riffRefusals", message: "zero and oversize RIFF errors retain fork text")
        }
    }
    let empty = PlaybackTimeline.build(file: MidiFile(), sampleRate: Double(exportRate))
    let emptyPath = FileManager.default.temporaryDirectory.appendingPathComponent(
        "empty-export-\(UUID().uuidString).wav")
    var noTail = exportOptions
    noTail.tailSeconds = 0
    do {
        _ = try WavExport.render(
            to: emptyPath.path, timeline: empty, voices: nil,
            settings: AudioSettings(), options: noTail, progress: { _ in true })
        report.expect(false, cppID: "\(id)::emptyRefusal", message: "empty render must refuse")
    } catch {
        report.expect(
            error == .nothingToRender && !FileManager.default.fileExists(atPath: emptyPath.path),
            cppID: "\(id)::emptyRefusal", message: "empty render refuses before creating file")
    }
    runExportCaptureChecks(report)
}
