import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawCore
import PorydawDocument
import PorydawPlaybackNative

private enum CaptureCheckError: Error {
    case fixture(String)
}

private func capturePCM(_ path: URL) throws -> [Int16] {
    let data = try Data(contentsOf: path)
    guard data.count >= 44, (data.count - 44) % 2 == 0 else {
        throw CaptureCheckError.fixture("invalid WAV PCM: \(path.path)")
    }
    func le16(_ offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
    }
    return stride(from: 44, to: data.count, by: 2).map(le16)
}

@MainActor
private func captureJourney(_ label: String, report: CheckReport) throws {
    let id = "exportcheck/WavExportCapture::\(label)"
    guard let root = CheckEnvironment.fixtureRoot else {
        throw CaptureCheckError.fixture("staged project root is missing")
    }
    let service = ProjectService()
    try runBlocking { try await service.open(root: root) }
    let session = try runBlocking { try await DocumentSession.open(service: service, label: label) }
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("export-capture-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let options = WavExportOptions(
        sampleRate: 44_100, loopCount: 1,
        fadeoutSeconds: 1, tailSeconds: 1)
    let songConfig = session.document.state.config
    let settings = AudioSettings().applyingSong(songConfig)
    let midiPath = root + "/sound/songs/midi/\(label).mid"
    let bankPath = root + "/" + session.bankLease.sourcePath
    let midiBefore = try Data(contentsOf: URL(filePath: midiPath))
    let bankBefore = try Data(contentsOf: URL(filePath: bankPath))

    func render(_ capture: WavExportCapture, _ name: String) throws -> (WavExportOutcome, [Int16]) {
        let path = scratch.appendingPathComponent("\(name).wav")
        let outcome = try runBlocking { await WavExportJob.run(capture, to: path.path, progress: nil) }
        guard case .completed = outcome else {
            throw CaptureCheckError.fixture("\(name) render failed: \(outcome)")
        }
        return (outcome, try capturePCM(path))
    }

    let a = session.wavExportCapture(settings: settings, options: options)
    let (_, pcmA) = try render(a, "before-note")
    // Keep the edit inside the first rendered pass, including the looping fixture.
    let addedNotes = try session.document.addNotes([
        NewNote(track: 0, tick: 6, pitch: 74, duration: 24, velocity: 110)
    ])
    report.expect(!addedNotes.isEmpty, cppID: id, message: "the captured note edit adds a note")
    let b = session.wavExportCapture(settings: settings, options: options)
    let revision = session.document.revision
    let undoCount = session.document.history.undoCount
    let (_, pcmB) = try render(b, "after-note")
    report.expect(
        pcmA != pcmB, cppID: id,
        message: "an export capture renders the unsaved note edit")
    let midiAfter = try Data(contentsOf: URL(filePath: midiPath))
    report.expect(
        session.document.isDirty && session.document.revision == revision
            && session.document.history.undoCount == undoCount && midiAfter == midiBefore,
        cppID: id, message: "exporting leaves the document dirty, unsaved and out of history")

    let program = session.document.state.file.chunks.lazy.flatMap(\.events).compactMap { event -> Int? in
        guard case .channel(let status, let slot, _) = event.payload, status & 0xF0 == 0xC0 else {
            return nil
        }
        return Int(slot)
    }.first
    guard let slot = program, session.bankSlots.indices.contains(slot),
        let original = session.bankSlots[slot].voice
    else {
        throw CaptureCheckError.fixture("\(label) first program has no editable bank voice")
    }
    var edited = original
    edited.release = original.release == 1 ? 255 : 1
    let bankEdit = try runBlocking {
        try await session.applyBankEdit(slot: slot, value: edited, expected: original)
    }
    report.expect(
        bankEdit.lease === session.bankLease && bankEdit.dirty,
        cppID: id, message: "the bank edit replaces the lease and remains unsaved")
    let c = session.wavExportCapture(settings: settings, options: options)
    report.expect(
        c.lease === session.bankLease && c.lease !== a.lease, cppID: id,
        message: "an export capture holds the mounted bank's unsaved lease")
    let (_, pcmC) = try render(c, "after-bank")
    report.expect(
        pcmC != pcmB, cppID: id,
        message: "an export capture renders the mounted bank's unsaved edit")
    let bankAfter = try Data(contentsOf: URL(filePath: bankPath))
    report.expect(
        session.bankDirty && bankAfter == bankBefore,
        cppID: id, message: "exporting leaves the bank edit unsaved")

    let closeOutcome = try runBlocking { await session.close() }
    report.expect(closeOutcome, cppID: id, message: "the captured session closes successfully")
    try runBlocking { await service.close() }
    let (rerendered, pcmAgain) = try render(c, "after-close")
    report.expect(
        rerendered == .completed(totalFrames: UInt64(pcmAgain.count / 2))
            && pcmAgain == pcmC, cppID: id,
        message: "a capture outlives its closed session and service")

    let cancelPath = scratch.appendingPathComponent("cancel.wav")
    let cancelled = try runBlocking {
        let task = Task { await WavExportJob.run(c, to: cancelPath.path, progress: nil) }
        task.cancel()
        return await task.value
    }
    report.expect(
        cancelled == .cancelled && !FileManager.default.fileExists(atPath: cancelPath.path),
        cppID: id, message: "a cancelled export job reports cancellation and leaves no file")

    let (stream, continuation) = AsyncStream.makeStream(
        of: Double.self, bufferingPolicy: .bufferingNewest(1))
    let progressPath = scratch.appendingPathComponent("progress.wav")
    let (progressOutcome, fractions) = try runBlocking {
        async let result = WavExportJob.run(c, to: progressPath.path, progress: continuation)
        var fractions: [Double] = []
        for await fraction in stream { fractions.append(fraction) }
        return await (result, fractions)
    }
    report.expect(
        {
            guard case .completed = progressOutcome, fractions.last == 1.0 else { return false }
            return zip(fractions, fractions.dropFirst()).allSatisfy { $0.0 < $0.1 }
        }(), cppID: id, message: "the export progress stream is monotonic and finishes at 1.0")

    var engine = AudioSettings()
    engine.pcmMixer = M4A_PCM_MIXER_SAPPY
    engine.maxPcmChannels = 9
    engine.pcmMixRate = 22_050
    engine.analogFilter = true
    var config = songConfig
    config.reverb = nil
    let defaulted = engine.applyingSong(config)
    config.reverb = 30
    let explicit = engine.applyingSong(config)
    report.expect(
        defaulted.pcmMixer == engine.pcmMixer
            && defaulted.maxPcmChannels == engine.maxPcmChannels
            && defaulted.pcmMixRate == engine.pcmMixRate
            && defaulted.analogFilter == engine.analogFilter
            && defaulted.reverb == 50 && explicit.reverb == 30
            && defaulted.songVolume == UInt8(clamping: config.masterVolume)
            && explicit.songVolume == UInt8(clamping: config.masterVolume),
        cppID: id,
        message: "song settings keep engine fields and apply the song volume and default reverb")
}

@MainActor
internal func runExportCaptureChecks(_ report: CheckReport) {
    let labels = ["mus_route101", "mus_route102"].filter {
        CheckEnvironment.fixturePath("sound/songs/midi/\($0).mid")
            .map { FileManager.default.fileExists(atPath: $0) } == true
    }
    guard !labels.isEmpty else {
        report.fail("exportcheck/WavExportCapture", "no capture fixture labels are staged")
        return
    }
    for label in labels {
        do {
            try captureJourney(label, report: report)
        } catch {
            report.fail("exportcheck/WavExportCapture::\(label)", "capture journey failed: \(error)")
        }
    }
}
