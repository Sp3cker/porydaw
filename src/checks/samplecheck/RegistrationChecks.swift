import Foundation
import PorydawAppAudio
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative
import PorydawVoicegroupNative
import PorydawProject
import PorydawVoicegroup
import PorydawSample
@testable import SwiftCoreCheckLogic

private func succeeded<Value, Failure: Error>(_ result: Result<Value, Failure>) -> Bool {
    if case .success = result { return true }
    return false
}

internal func runRegistrationChecks(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: root) }
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::projectProbe")
    do {
        let wavRoot = root + "/wavproj"
        try writeWav2AgbProject(root: wavRoot)
        let probe = SampleRegistrar.probe(projectRoot: wavRoot)
        check.expect(probe.ok && probe.pipeline == .wav2agb, message: "A003 wav2agb project probes OK")
        let aifRoot = root + "/aifproj"
        try writeAif2PcmProject(root: aifRoot)
        let aif = SampleRegistrar.probe(projectRoot: aifRoot)
        check.expect(aif.pipeline == .legacyAif, message: "A006 legacy AIF pipeline detected")
        check.expect(aif.refusal.contains("predates wav2agb"), message: "A007 legacy AIFF project layout is refused")
        let noRule = root + "/norule"
        try FileManager.default.createDirectory(at: URL(filePath: noRule + "/sound"), withIntermediateDirectories: true)
        try Data().write(to: URL(filePath: noRule + "/sound/direct_sound_data.inc"))
        check.expect(
            !SampleRegistrar.probe(projectRoot: noRule).refusal.isEmpty,
            message: "A009 unsupported project layout is refused")
        let noInc = root + "/noinc"
        try FileManager.default.createDirectory(at: URL(filePath: noInc), withIntermediateDirectories: true)
        try Data("$(SOUND_BIN_DIR)/%.bin: sound/%.wav\n\t$(WAV2AGB) -b $< $@\n".utf8)
            .write(to: URL(filePath: noInc + "/audio_rules.mk"))
        check.expect(
            !SampleRegistrar.probe(projectRoot: noInc).refusal.isEmpty,
            message: "A011 missing registration anchor is refused")
        registrationNames(report, root: wavRoot)
        registrationWrites(report, root: wavRoot)
    } catch {
        report.scoped(cppID: "swiftcore/SampleRegistrar::fixture").expect(
            false,
            message: "registration fixture failed: \(error)")
    }
    runRegistrationParityChecks(report)
    registrationEngineLoop(report)
}

private func registrationNames(_ report: CheckReport, root: String) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::projectSanitizeValidate")
    check.expect(SampleNames.sanitize("My Sample #2") == "my_sample_2", message: "A014 sanitize sample name")
    check.expect(SampleNames.sanitize("Bell (C5)") == "bell_c5", message: "A015 sanitize pitched name")
    let symbols = VoicegroupSource.directSoundSymbols(root)
    check.expect(
        SampleRegistrar.validate(projectRoot: root, name: "fresh_tone", existingSymbols: symbols) == nil,
        message: "A016 fresh sample name accepted")
    check.expect(
        SampleRegistrar.validate(projectRoot: root, name: "", existingSymbols: symbols) != nil,
        message: "A018 rejected empty name reports refusal")
    check.expect(
        SampleRegistrar.validate(projectRoot: root, name: "Bad Name", existingSymbols: symbols) != nil,
        message: "A019 invalid grammar refused")
    check.expect(
        SampleRegistrar.validate(projectRoot: root, name: "existing", existingSymbols: symbols) != nil,
        message: "A021 duplicate symbol refused")
    check.expect(
        SampleRegistrar.validate(projectRoot: root, name: "orphan", existingSymbols: symbols) != nil,
        message: "A023 orphan source refused")
}

private func registrationWrites(_ report: CheckReport, root: String) {
    let register = report.scoped(cppID: "samplecheck/SampleProcessingTest::projectRegister")
    let wav = preparedSampleWav()
    let inc = root + "/sound/direct_sound_data.inc"
    let seed = (try? Data(contentsOf: URL(filePath: inc))) ?? Data()
    let registration = Result {
        try SampleRegistrar.register(projectRoot: root, name: "samplecheck_tone", wav: wav)
    }
    register.expect(succeeded(registration), message: "A042 sample registers")
    guard succeeded(registration) else { return }
    register.expect(
        (try? Data(contentsOf: URL(filePath: root + "/sound/direct_sound_samples/samplecheck_tone.wav"))) == wav,
        message: "A043 registered WAV bytes equal fixture")
    let block =
        "\n\t.align 2\nDirectSoundWaveData_samplecheck_tone::\n\t.incbin \"sound/direct_sound_samples/samplecheck_tone.bin\"\n"
    let grown = (try? Data(contentsOf: URL(filePath: inc))) ?? Data()
    register.expect(grown == seed + Data(block.utf8), message: "A044 assembly registration bytes preserve seed")
    let symbols = VoicegroupSource.directSoundSymbols(root)
    register.expect(
        symbols.contains("DirectSoundWaveData_samplecheck_tone") && symbols.contains("DirectSoundWaveData_existing"),
        message: "A045 fresh and existing symbols resolve")
    let voiceFile = root + "/sound/voicegroups/voicegroup_samplecheck.inc"
    let fixture = Result {
        try FileManager.default.createDirectory(
            at: URL(filePath: voiceFile).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data(
            "voicegroup_samplecheck::\n\tvoice_directsound 60, 0, DirectSoundWaveData_samplecheck_tone, 255, 165, 90, 178\n"
                .utf8
        )
        .write(to: URL(filePath: voiceFile))
    }
    register.expect(succeeded(fixture), message: "A046 voicegroup fixture written")
    if succeeded(fixture) {
        let loaded = root.withCString { project in
            "voicegroup_samplecheck".withCString { name in voicegroup_load(project, name, nil) }
        }
        register.expect(loaded != nil, message: "A047 registered sample resolves through native loader")
        if let loaded {
            defer { voicegroup_free(loaded) }
            let tone = loaded.pointee.voices.0
            register.expect(
                tone.type == 0 && tone.key == 60 && tone.attack == 255 && tone.decay == 165
                    && tone.sustain == 90 && tone.release == 178, message: "A048 loaded voice ADSR matches")
            if let wave = tone.wav {
                let value = wave.pointee
                register.expect(
                    value.freq == 15_000_000 && value.loopStart == 8 && value.size == 64
                        && value.status == 0x4000 && value.data != nil, message: "A049 loaded wave metadata matches")
                register.expect(
                    value.data.map { data in (0..<64).allSatisfy { Int(data[$0]) == $0 * 2 - 128 } } ?? false,
                    message: "A050 loaded wave signed bytes match")
            } else {
                register.expect(false, message: "A049 loaded wave metadata matches")
                register.expect(false, message: "A050 loaded wave signed bytes match")
            }
            let name = withUnsafePointer(to: loaded.pointee.voiceNames.0) {
                $0.withMemoryRebound(to: CChar.self, capacity: 48) { String(cString: $0) }
            }
            register.expect(name == "samplecheck_tone", message: "A051 loaded voice name matches symbol")
        }
    }

    let duplicate = report.scoped(cppID: "samplecheck/SampleProcessingTest::projectDuplicate")
    let duplicateRoot = root + "/../duplicateproj"
    do {
        try writeWav2AgbProject(root: duplicateRoot)
        let first = Result {
            try SampleRegistrar.register(projectRoot: duplicateRoot, name: "samplecheck_tone", wav: wav)
        }
        duplicate.expect(succeeded(first), message: "A054 first sample registers before duplicate")
        guard succeeded(first) else { return }
        let duplicateInc = duplicateRoot + "/sound/direct_sound_data.inc"
        let before = try Data(contentsOf: URL(filePath: duplicateInc))
        let second = Result {
            try SampleRegistrar.register(projectRoot: duplicateRoot, name: "samplecheck_tone", wav: Data([0]))
        }
        duplicate.expect(!succeeded(second), message: "A055 duplicate sample refused")
        let refusalMessage: String?
        if case .failure(let error) = second {
            refusalMessage = (error as? SampleRegistrationError)?.message
        } else {
            refusalMessage = nil
        }
        duplicate.expect(refusalMessage?.isEmpty == false, message: "A056 duplicate reports actionable refusal")
        let after = try Data(contentsOf: URL(filePath: duplicateInc))
        duplicate.expect(after == before, message: "A057 duplicate leaves assembly bytes untouched")
    } catch {
        report.scoped(cppID: "swiftcore/SampleRegistrar::duplicateFixture").expect(
            false,
            message: "duplicate fixture failed: \(error)")
    }

    let crlf = report.scoped(cppID: "samplecheck/SampleProcessingTest::projectCrlf")
    let crlfRoot = root + "/../crlfproj"
    do {
        try writeWav2AgbProject(root: crlfRoot)
        let crlfInc = crlfRoot + "/sound/direct_sound_data.inc"
        let crlfSeed = Data(
            "  .align 2\r\nDirectSoundWaveData_existing::\r\n    .incbin \"sound/direct_sound_samples/existing.bin\"\r\n"
                .utf8)
        try crlfSeed.write(to: URL(filePath: crlfInc))
        let result = Result { try SampleRegistrar.register(projectRoot: crlfRoot, name: "crlf_tone", wav: wav) }
        let expected =
            crlfSeed
            + Data(
                "\r\n  .align 2\r\nDirectSoundWaveData_crlf_tone::\r\n    .incbin \"sound/direct_sound_samples/crlf_tone.bin\"\r\n"
                    .utf8)
        crlf.expect(succeeded(result), message: "A061 CRLF sample registers")
        guard succeeded(result) else { return }
        let actual = try Data(contentsOf: URL(filePath: crlfInc))
        crlf.expect(actual == expected, message: "A062 CRLF assembly preserves exact EOL and indents")
        crlf.expect(
            actual.enumerated().allSatisfy { $0.element != 10 || ($0.offset > 0 && actual[$0.offset - 1] == 13) },
            message: "A063 every CRLF line retains carriage return")
    } catch {
        report.scoped(cppID: "swiftcore/SampleRegistrar::crlfFixture").expect(
            false,
            message: "CRLF fixture failed: \(error)")
    }
}
func runRegistrationParityChecks(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::parityCases")
    let imported = Result { try importedHiRes() }
    check.expect(succeeded(imported), message: "A037 parity high-resolution source imports")
    guard case .success(let source) = imported else { return }
    for (profile, name): (ParityProfile, String) in [
        (.a, "pm_a"), (.b, "pm_b"), (.c, "pm_c"),
        (.d, "pm_d"), (.e, "pm_e"), (.f, "pm_f"),
    ] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        do {
            try writeWav2AgbProject(root: root)
            let params = parityParams(
                profile, sourceRate: source.sampleRate,
                params: SampleDocument.defaultParams(for: source))
            var document = SampleDocument(source: source)
            document.setParams(params)
            let render = document.processed
            let bytes = SampleWavWriter.bytes(for: render)
            let registration = Result { try SampleRegistrar.register(projectRoot: root, name: name, wav: bytes) }
            check.expect(succeeded(registration), message: "A038 parity rendered sample registers")
            guard succeeded(registration) else { continue }
            let written = try Data(contentsOf: URL(filePath: root + "/sound/direct_sound_samples/" + name + ".wav"))
            let b = [UInt8](written)
            let chunks = readRiffChunks(b)
            check.expect(
                chunks.map { parsed in
                    ["fmt ", "data", "smpl", "agbp", "agbl"].allSatisfy { name in
                        parsed.contains { $0.name == name }
                    }
                } == true, message: "A039 written sample RIFF chunks parse")
            guard let chunks,
                let fmt = chunks.first(where: { $0.name == "fmt " }),
                let data = chunks.first(where: { $0.name == "data" }),
                let smpl = chunks.first(where: { $0.name == "smpl" }),
                let pitch = chunks.first(where: { $0.name == "agbp" }),
                let end = chunks.first(where: { $0.name == "agbl" })
            else { continue }
            let midiKey = getU32(b, smpl.start + 8 + 12)
            let fraction = getU32(b, smpl.start + 8 + 16)
            let loopCount = getU32(b, smpl.start + 8 + 28)
            let loopStart = loopCount > 0 ? getU32(b, smpl.start + 8 + 44) : 0
            let loopEnd = loopCount > 0 ? getU32(b, smpl.start + 8 + 48) : 0
            check.expect(
                getU32(b, pitch.start + 8) == render.freq && getU32(b, end.start + 8) == render.size
                    && data.size == Int(render.size) && getU32(b, fmt.start + 8 + 4) == render.declaredRate
                    && midiKey == UInt32(render.unityNote) && fraction == render.pitchFraction,
                message: "A040 WAV metadata matches rendered frequency, rate, pitch and size")
            check.expect(
                (loopCount == 1) == render.looped
                    && (!render.looped || (loopStart == render.loopStart && loopEnd == render.size - 1)),
                message: "A041 WAV forward-loop bounds match render")
            check.expect(
                getU32(b, pitch.start + 8) == render.freq && getU32(b, end.start + 8) == render.size
                    && loopStart == render.loopStart, message: "A042 loader-derived header matches render")
            let exactKey = Double(params.baseKey) + params.fineTuneCents / 100
            let actualKey = Double(midiKey) + Double(fraction) / 4_294_967_296
            check.expect(
                abs(actualKey - exactKey) < 0.000001,
                message: "A043 WAV fractional pitch matches exact key")
            let voiceFile = root + "/sound/voicegroups/voicegroup_parity.inc"
            try FileManager.default.createDirectory(
                at: URL(filePath: voiceFile).deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(
                "voicegroup_parity::\n\tvoice_directsound 60, 0, DirectSoundWaveData_\(name), 255, 0, 255, 0\n".utf8
            )
            .write(to: URL(filePath: voiceFile))
            let loaded = root.withCString { project in
                "voicegroup_parity".withCString { symbol in voicegroup_load(project, symbol, nil) }
            }
            check.expect(loaded != nil, message: "A045 parity voicegroup resolves")
            guard let loaded else { continue }
            defer { voicegroup_free(loaded) }
            let wave = loaded.pointee.voices.0.wav
            check.expect(wave?.pointee.data != nil, message: "A046 parity voice resolves sample bytes")
            guard let wave else { continue }
            check.expect(wave.pointee.freq == render.freq, message: "A047 loaded frequency equals render")
            check.expect(wave.pointee.loopStart == render.loopStart, message: "A048 loaded loop start equals render")
            check.expect(wave.pointee.size == render.size, message: "A049 loaded size equals render")
            check.expect(
                wave.pointee.status == (render.looped ? 0x4000 : 0),
                message: "A050 loaded loop status equals render")
            check.expect(
                wave.pointee.data.map { samples in render.s8.indices.allSatisfy { samples[$0] == render.s8[$0] } }
                    ?? false,
                message: "A051 loaded signed PCM equals render")
        } catch {
            report.scoped(cppID: "swiftcore/SampleRegistrar::parityFixture").expect(
                false,
                message: "parity fixture \(name) failed: \(error)")
        }
    }
}

private func registrationEngineLoop(_ report: CheckReport) {
    let check = report.scoped(cppID: "samplecheck/SampleProcessingTest::engineLoop")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: root) }
    do {
        try writeWav2AgbProject(root: root)
        let imported = Result { try importedHiRes() }
        check.expect(succeeded(imported), message: "A003 engine-loop high-resolution source imports")
        guard case .success(let source) = imported else { return }
        var document = SampleDocument(source: source)
        var params = document.params
        params.targetRate = 13379
        document.setParams(params)
        let render = document.processed
        check.expect(
            render.looped && render.size > render.loopStart + 100,
            message: "A004 engine-loop fixture renders looped")
        let registration = Result {
            try SampleRegistrar.register(
                projectRoot: root, name: "engineloop_tone",
                wav: SampleWavWriter.bytes(for: render))
        }
        check.expect(succeeded(registration), message: "A005 engine-loop sample registers")
        guard succeeded(registration) else { return }
        let file = root + "/sound/voicegroups/voicegroup_engineloop.inc"
        try FileManager.default.createDirectory(
            at: URL(filePath: file).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data(
            "voicegroup_engineloop::\n\tvoice_directsound 60, 0, DirectSoundWaveData_engineloop_tone, 255, 0, 255, 0\n"
                .utf8
        )
        .write(to: URL(filePath: file))
        let loaded = root.withCString { path in
            "voicegroup_engineloop".withCString { voice in voicegroup_load(path, voice, nil) }
        }
        check.expect(loaded != nil, message: "A007 engine-loop voicegroup resolves")
        guard let loaded else { return }
        defer { voicegroup_free(loaded) }
        let hostRate = (Double(render.freq) / 1024).rounded()
        let native = m4a_engine_create(Float(hostRate))
        check.expect(native != nil, message: "A008 engine-loop initializes at integral host rate")
        guard let native else { return }
        defer { m4a_engine_free(native) }
        let wrapped = Result { try AudioRenderEngine(sampleRate: hostRate, periodFrames: 512) }
        guard case .success(let engine) = wrapped else {
            report.scoped(cppID: "swiftcore/SampleRegistrar::engineFixture").expect(
                false,
                message: "audio render engine failed: \(wrapped)")
            return
        }
        let loopLength = Int(render.size - render.loopStart)
        let measurementStart = Int(render.size) + 4 * loopLength
        let frames = measurementStart + loopLength
        check.expect(frames <= 400_000, message: "A010 engine-loop fixture fits render window")
        guard frames <= 400_000 else { return }
        let midi = MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 4800),
                MidiChunk(
                    events: [
                        .channel(tick: 0, status: 0xC0, data0: 0),
                        .channel(tick: 0, status: 0x90, data0: 60, data1: 127),
                        .channel(tick: 4800, status: 0xB0, data0: 7, data1: 100),
                    ], endTick: 4800),
            ])
        let timeline = PlaybackTimeline.build(file: midi, sampleRate: hostRate)
        var buffer = [Float](repeating: 0, count: frames * 2)
        var activeAfterFourWraps = false
        withUnsafeMutablePointer(to: &loaded.pointee.voices.0) { voices in
            m4a_engine_set_pcm_mix_rate(native, 0)
            m4a_engine_set_voicegroup(native, voices)
            m4a_engine_program_change(native, 0, 0)
            m4a_engine_note_on(native, 0, 60, 127)
            let synchronousChannel = withUnsafePointer(to: &native.pointee.pcmChannels) { storage in
                let channels = UnsafeRawPointer(storage).assumingMemoryBound(to: M4APCMChannel.self)
                let count = MemoryLayout.size(ofValue: storage.pointee) / MemoryLayout<M4APCMChannel>.stride
                return (0..<count).contains { channels[$0].status & playbackCheckChannelOn != 0 }
            }
            check.expect(synchronousChannel, message: "A009 engine-loop note keys audible channel")
            engine.bind(timeline: timeline, voicegroup: voices, settings: AudioSettings())
            engine.setLoopEnabled(false)
            engine.play()
            buffer.withUnsafeMutableBufferPointer { pcm in
                guard let base = pcm.baseAddress else { return }
                var done = 0
                while done < frames {
                    let n = min(512, frames - done)
                    engine.render(base + done * 2, frames: UInt32(n))
                    done += n
                }
            }
            activeAfterFourWraps = engine.activePcmChannels > 0
            engine.unload()
        }
        let signal = stride(from: measurementStart, to: frames, by: 1).map { Double(buffer[$0 * 2]) }
        let peak = signal.reduce(0.0) { max($0, abs($1)) }
        check.expect(
            activeAfterFourWraps && peak > 0 && signal.count == loopLength,
            message: "A011 at least four full loop wraps render")
        var maxS8 = 1
        var maxSourceStep = 0
        for index in Int(render.loopStart)..<Int(render.size) {
            let sample = Int(render.s8[index])
            let next = Int(render.s8[index + 1 < Int(render.size) ? index + 1 : Int(render.loopStart)])
            maxS8 = max(maxS8, abs(sample))
            maxSourceStep = max(maxSourceStep, abs(next - sample))
        }
        var previous = Double(buffer[(measurementStart - 1) * 2])
        var maxStep = 0.0
        for value in signal {
            maxStep = max(maxStep, abs(value - previous))
            previous = value
        }
        let lsb = peak / Double(maxS8)
        check.expect(
            maxStep <= Double(maxSourceStep) * lsb + 2 * lsb + 1e-9,
            message: "A012 loop-wrap steps stay within source steps plus two LSB")
    } catch {
        report.scoped(cppID: "swiftcore/SampleRegistrar::engineFixture").expect(
            false,
            message: "engine-loop fixture failed: \(error)")
    }
}
