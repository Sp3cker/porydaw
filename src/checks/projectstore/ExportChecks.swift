import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawCore
import PorydawPlaybackNative

private enum ExportCheckError: Error {
    case failed(String)
}

private let exportRate = 44_100
private let exportChunk = 4_096

private struct ExportFixture {
    let song: LoadedSong
    let timeline: PlaybackTimeline
    let scratch: URL

    var hasLoop: Bool { timeline.hasLoop }
    var fadeStart: UInt64 {
        hasLoop ? timeline.loopEndSample : .max
    }
    var totalFrames: UInt64 {
        hasLoop ? fadeStart + UInt64(exportRate) : timeline.lengthSamples + UInt64(exportRate)
    }
}

private func exportRequire(_ condition: Bool, _ reason: String) throws {
    guard condition else { throw ExportCheckError.failed(reason) }
}


@MainActor
private func withExportFixture(label: String, _ body: (ExportFixture) throws -> Void) throws {
    var isDirectory: ObjCBool = false
    guard let root = CheckEnvironment.fixtureRoot,
          FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw ExportCheckError.failed("exportcheck project root is not a directory: \(CheckEnvironment.fixtureRoot ?? "")")
    }
    guard !label.isEmpty else {
        throw ExportCheckError.failed("exportcheck requires a song label")
    }
    try withTempProjectCopy(prefix: "exportcheck") { scratch in
        let service = ProjectService()
        let outcome = Result {
            try runBlocking { try await service.open(root: scratch.path) }
            let song = try runBlocking { try await service.openSong(label: label) }
            let file = try MidiFile.decode(song.midiBytes)
            let timeline = PlaybackTimeline.build(
                file: file, sampleRate: Double(exportRate),
                settings: PlaybackSettings(exactGate: song.config.exactGate,
                                           extendedClocks: song.config.extendedClocks))
            try body(ExportFixture(song: song, timeline: timeline, scratch: scratch))
        }
        try runBlocking { await service.close() }
        try outcome.get()
    }
}

private func appendU16(_ value: UInt16, to bytes: inout Data) {
    bytes.append(UInt8(truncatingIfNeeded: value))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
}

private func appendU32(_ value: UInt32, to bytes: inout Data) {
    for shift in stride(from: 0, to: 32, by: 8) {
        bytes.append(UInt8(truncatingIfNeeded: value >> shift))
    }
}

private func wavHeader(frames: UInt64) throws -> Data {
    try exportRequire(frames <= (UInt64(UInt32.max) - 36) / 4,
                      "The rendered file would exceed the 4 GB WAV limit")
    let dataSize = frames * 4
    var bytes = Data()
    bytes.reserveCapacity(44)
    bytes.append(contentsOf: "RIFF".utf8)
    appendU32(UInt32(36 + dataSize), to: &bytes)
    bytes.append(contentsOf: "WAVEfmt ".utf8)
    appendU32(16, to: &bytes)
    appendU16(1, to: &bytes)
    appendU16(2, to: &bytes)
    appendU32(UInt32(exportRate), to: &bytes)
    appendU32(UInt32(exportRate * 4), to: &bytes)
    appendU16(4, to: &bytes)
    appendU16(16, to: &bytes)
    bytes.append(contentsOf: "data".utf8)
    appendU32(UInt32(dataSize), to: &bytes)
    return bytes
}

private func pcm16(_ sample: Float) -> UInt16 {
    let value = Int32(sample * 32_767)
    return UInt16(bitPattern: Int16(clamping: value))
}

/// Returns false only when the progress callback cancelled; errors throw.
private func renderExport(
    _ fixture: ExportFixture, at path: URL, suppress: Bool = false,
    progress: (Double) -> Bool = { _ in true }
) throws -> Bool {
    try exportRequire(fixture.totalFrames > 0, "Nothing to render.")
    let header = try wavHeader(frames: fixture.totalFrames)
    var completed = false
    var renderedEntireSong = false
    // On cancellation or failure the partially written WAV must not survive.
    defer { if !completed { try? FileManager.default.removeItem(at: path) } }
    _ = FileManager.default.createFile(atPath: path.path, contents: nil)
    let output = try FileHandle(forWritingTo: path)
    do {
        try output.write(contentsOf: header)
        guard progress(0) else {
            try output.close()
            return false
        }
        try fixture.song.bank.withVoices { voices in
            guard voices != nil else {
                throw ExportCheckError.failed("song bank has no native voices")
            }
            let renderer = try AudioRenderEngine(sampleRate: Double(exportRate),
                                                 periodFrames: exportChunk)
            var settings = AudioSettings()
            settings.songVolume = UInt8(clamping: fixture.song.config.masterVolume)
            settings.reverb = UInt8(clamping: max(0, fixture.song.config.reverb ?? 0))
            renderer.bind(timeline: fixture.timeline, voicegroup: voices, settings: settings)
            renderer.setLoopEnabled(fixture.hasLoop)
            renderer.setResonanceSuppression(suppress)
            renderer.play()
            let floats = UnsafeMutablePointer<Float>.allocate(capacity: exportChunk * 2)
            defer { floats.deallocate() }
            var pcm = Data()
            pcm.reserveCapacity(exportChunk * 4)
            let fadeLength = fixture.hasLoop ? fixture.totalFrames - fixture.fadeStart : 0
            var position: UInt64 = 0
            while position < fixture.totalFrames {
                let count = Int(min(UInt64(exportChunk), fixture.totalFrames - position))
                renderer.render(floats, frames: UInt32(count))
                pcm.removeAll(keepingCapacity: true)
                for frame in 0..<count {
                    let sample = position + UInt64(frame)
                    let gain: Float = sample >= fixture.fadeStart
                        ? 1 - Float(sample - fixture.fadeStart) / Float(fadeLength) : 1
                    appendU16(pcm16(floats[frame * 2] * gain), to: &pcm)
                    appendU16(pcm16(floats[frame * 2 + 1] * gain), to: &pcm)
                }
                try output.write(contentsOf: pcm)
                position += UInt64(count)
                if !progress(Double(position) / Double(fixture.totalFrames)) {
                    return
                }
            }
            renderedEntireSong = true
        }
        try output.close()
        completed = renderedEntireSong
        return completed
    } catch {
        // The output is already failing; closing is best-effort before removal.
        try? output.close()
        throw error
    }
}

private func le16(_ bytes: Data, _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
}

private func le32(_ bytes: Data, _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
        UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
}

@MainActor
private func exportCase(_ name: String, labels: [String], _ report: CheckReport,
                        _ body: (ExportFixture) throws -> Void) {
    let cppID = "exportcheck/MidiExportTest::\(name)"
    for label in labels {
        do {
            try withExportFixture(label: label, body)
            report.pass(cppID, row: "\(name)[\(label)]")
        } catch {
            report.fail(cppID, "\(name)[\(label)]: \(error)")
        }
    }
}

@MainActor
internal func runExportChecks(_ report: CheckReport) {
    let labels = ["mus_route101", "mus_route102"].filter {
        CheckEnvironment.fixturePath("sound/songs/midi/\($0).mid")
            .map { FileManager.default.fileExists(atPath: $0) } == true
    }
    let stagedLabels = labels.isEmpty ? [""] : labels
    exportCase("durationCalculationMatchesRenderParity", labels: stagedLabels, report) { fixture in
        let expected = fixture.hasLoop
            ? fixture.timeline.loopStartSample +
                (fixture.timeline.loopEndSample - fixture.timeline.loopStartSample) + UInt64(exportRate)
            : fixture.timeline.lengthSamples + UInt64(exportRate)
        let path = fixture.scratch.appendingPathComponent("parity.wav")
        try exportRequire(try renderExport(fixture, at: path), "duration render was cancelled")
        let bytes = try Data(contentsOf: path)
        try exportRequire(bytes.count == 44 + Int(expected) * 4,
                          "calculated duration differs from rendered frame count")
    }

    exportCase("offlineExportProducesValidRiffPcm", labels: stagedLabels, report) { fixture in
        let path = fixture.scratch.appendingPathComponent("export.wav")
        var lastFraction = -1.0
        var monotonic = true
        try exportRequire(try renderExport(fixture, at: path) { fraction in
            monotonic = monotonic && fraction > lastFraction
            lastFraction = fraction
            return true
        }, "WAV export was cancelled")
        try exportRequire(monotonic && lastFraction == 1,
                          "WAV export progress was not strictly monotonic through 1.0")
        let wav = try Data(contentsOf: path)
        try exportRequire(wav.count == 44 + Int(fixture.totalFrames) * 4,
                          "WAV byte count does not match the rendered frame count")
        try exportRequire(wav.count >= 44 && String(decoding: wav[0..<4], as: UTF8.self) == "RIFF" &&
                          String(decoding: wav[8..<12], as: UTF8.self) == "WAVE" &&
                          String(decoding: wav[12..<16], as: UTF8.self) == "fmt " &&
                          String(decoding: wav[36..<40], as: UTF8.self) == "data" &&
                          le32(wav, 4) == UInt32(wav.count - 8) && le32(wav, 16) == 16 &&
                          le16(wav, 20) == 1 && le16(wav, 22) == 2 &&
                          le32(wav, 24) == UInt32(exportRate) &&
                          le32(wav, 28) == UInt32(exportRate * 4) &&
                          le16(wav, 32) == 4 && le16(wav, 34) == 16 &&
                          le32(wav, 40) == UInt32(fixture.totalFrames * 4),
                          "export did not produce a valid RIFF/stereo PCM header")
        var peak = 0
        var tailPeak = 0
        for sample in stride(from: 44, to: wav.count, by: 2) {
            let magnitude = abs(Int(Int16(bitPattern: le16(wav, sample))))
            peak = max(peak, magnitude)
            if fixture.hasLoop && sample >= wav.count - 16 * 4 {
                tailPeak = max(tailPeak, magnitude)
            }
        }
        try exportRequire(peak >= 256, "offline WAV render is nearly silent")
        if fixture.hasLoop {
            try exportRequire(fixture.totalFrames >= 16,
                              "looping export is too short for tail verification")
            try exportRequire(tailPeak <= peak / 16, "looping WAV export did not fade to silence")
        }
    }

    exportCase("resonanceSuppressionChangesPcmWithoutChangingFrames",
               labels: stagedLabels, report) { fixture in
        let baseline = fixture.scratch.appendingPathComponent("baseline.wav")
        let suppressed = fixture.scratch.appendingPathComponent("suppressed.wav")
        try exportRequire(try renderExport(fixture, at: baseline), "baseline render was cancelled")
        try exportRequire(try renderExport(fixture, at: suppressed, suppress: true),
                          "suppressed render was cancelled")
        let before = try Data(contentsOf: baseline)
        let after = try Data(contentsOf: suppressed)
        try exportRequire(after.count == before.count, "suppression changed exported frame count")
        try exportRequire(after.dropFirst(44) != before.dropFirst(44),
                          "resonance suppression did not alter exported PCM bytes")
    }

    exportCase("cancelledExportRemovesPartialFile", labels: stagedLabels, report) { fixture in
        let path = fixture.scratch.appendingPathComponent("cancelled.wav")
        let completed = try renderExport(fixture, at: path, suppress: true) { fraction in fraction == 0 }
        try exportRequire(!completed, "cancelled export unexpectedly completed")
        try exportRequire(!FileManager.default.fileExists(atPath: path.path),
                          "cancelled WAV export left a partial file")
    }
}
