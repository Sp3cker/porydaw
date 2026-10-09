import Foundation
import PorydawApp
import PorydawProject
import PorydawVoicegroup
import PorydawVoicegroupNative
import PorydawSample

@MainActor
internal func runEditorPresenterChecks(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: root) }
    do {
        try writeWav2AgbProject(root: root)
        let prefill = report.scoped(cppID: "samplecheck/SampleProcessingTest::pipelinePrefillCollision")
        let preparedWav = preparedSampleWav()
        let registration = Result {
            try SampleRegistrar.register(projectRoot: root, name: "samplecheck_tone", wav: preparedWav)
        }
        guard case .success = registration else {
            report.scoped(cppID: "swiftcore/SampleStudioPresenter::fixture").expect(
                false,
                message: "registered source fixture refused")
            return
        }
        let path = root + "/sound/direct_sound_samples/samplecheck_tone.wav"
        let registeredBytes = try Data(contentsOf: URL(filePath: path))
        prefill.expect(registeredBytes == preparedWav, message: "A003 prepared sample registers")
        let decoded = Result { try SampleImport.decodeFile(path: path) }
        guard case .success(let imported) = decoded else {
            report.scoped(cppID: "swiftcore/SampleStudioPresenter::fixture").expect(
                false,
                message: "registered source could not re-import")
            return
        }
        prefill.expect(
            imported.gbaReady && imported.sourcePath == path,
            message: "A004 prepared sample re-imports from project")
        let validator: (String) -> String? = { name in
            SampleRegistrar.validate(
                projectRoot: root, name: name, existingSymbols: ["DirectSoundWaveData_samplecheck_tone"])
        }
        let presenter = SampleStudioPresenter(source: imported, validateName: validator)
        prefill.expect(presenter.sampleName == "samplecheck_tone", message: "A006 name prefilled from source file")
        prefill.expect(!presenter.canCommit, message: "A007 collision disables the commit")
        prefill.expect(!presenter.nameStatus.isEmpty, message: "A008 collision displays validation status")
        presenter.setSampleName(name: "fresh_tone")
        prefill.expect(presenter.canCommit, message: "A009 valid name enables the commit")
        prefill.expect(
            presenter.nameStatus == "Registers as DirectSoundWaveData_fresh_tone",
            message: "A010 valid name displays registration status")
        prefill.expect(presenter.sampleName == "fresh_tone", message: "A011 sampleName returns the edited name")
        presenter.setSampleName(name: "Bad Name")
        prefill.expect(!presenter.canCommit, message: "A012 bad grammar disables the commit")

        let defaults = report.scoped(cppID: "samplecheck/SampleProcessingTest::pipelinePreparedDefaults")
        let defaultSource = try SampleImport.decode(preparedWav, sourcePath: "fix/prepared_tone.wav")
        defaults.expect(
            defaultSource.gbaReady && defaultSource.frameCount == 64,
            message: "A013 prepared source imports")
        let defaultPresenter = SampleStudioPresenter(source: defaultSource, validateName: validator)
        let initial = defaultPresenter.processed
        defaults.expect(
            initial.freq == 15_000_000 && initial.size == 64 && initial.looped && initial.loopStart == 8,
            message: "A015 prepared defaults keep the source header verbatim")
        defaults.expect(
            defaultPresenter.baseKey == 58 && abs(defaultPresenter.fineTuneCents - 25) < 1e-9,
            message: "A016 key/cents prefilled from smpl")
        defaults.expect(
            initial.s8.count == 64
                && initial.s8.enumerated().allSatisfy { index, value in value == Int8(index * 2 - 128) },
            message: "A017 prepared defaults render the data verbatim")

        let pitch = report.scoped(cppID: "samplecheck/SampleProcessingTest::pipelineKeyOverride")
        let pitchSource = try SampleImport.decode(preparedWav, sourcePath: "fix/prepared_tone.wav")
        pitch.expect(
            pitchSource.exactPitch == 15_000_000 && pitchSource.baseKey == 58,
            message: "A018 key-override source imports")
        let pitchPresenter = SampleStudioPresenter(source: pitchSource, validateName: validator)
        pitchPresenter.setBaseKeyText(text: "B3")
        pitch.expect(
            pitchPresenter.params.baseKey == 59 && pitchPresenter.params.exactPitchOverride == 0
                && pitchPresenter.processed.freq != 15_000_000,
            message: "A020 key edit flows into the render and drops the override")
        pitchPresenter.setBaseKeyText(text: "A#3")
        pitch.expect(
            pitchPresenter.processed.freq == 15_000_000, message: "A021 restoring source key restores verbatim agbp")

        let rate = report.scoped(cppID: "samplecheck/SampleProcessingTest::pipelineRateCommit")
        let rateSource = try SampleImport.decode(preparedWav, sourcePath: "fix/prepared_tone.wav")
        rate.expect(rateSource.gbaReady && rateSource.hasLoop, message: "A025 rate source imports")
        let ratePresenter = SampleStudioPresenter(source: rateSource, validateName: validator)
        ratePresenter.setLoopOn(enabled: false)
        rate.expect(!ratePresenter.processed.looped, message: "A027 rate fixture is in one-shot mode")
        let beforeTyping = ratePresenter.renderRevision
        ratePresenter.rateText = "6689.5"
        rate.expect(
            ratePresenter.params.targetRate != 6689.5 && ratePresenter.renderRevision == beforeTyping,
            message: "A028 typing a rate does not re-render per keystroke")
        ratePresenter.commitRateText(text: ratePresenter.rateText)
        rate.expect(ratePresenter.params.targetRate == 6689.5, message: "A029 committed fractional target rate")
        rate.expect(
            ratePresenter.processed.declaredRate == 6690, message: "A030 fractional rate rounds declared WAV rate")
        rate.expect(ratePresenter.params.exactPitchOverride == 0, message: "A031 rate edit drops verbatim agbp")
        ratePresenter.chooseRate(index: 1)
        ratePresenter.chooseRate(index: 0)
        rate.expect(
            ratePresenter.params.targetRate == rateSource.sampleRate, message: "A032 preset pick restores source rate")

        let crop = report.scoped(cppID: "samplecheck/SampleProcessingTest::pipelineCropNormalize")
        let cropSource = try SampleImport.decode(preparedWav, sourcePath: "fix/prepared_tone.wav")
        crop.expect(cropSource.frameCount == 64 && cropSource.hasLoop, message: "A033 crop source imports")
        let cropPresenter = SampleStudioPresenter(source: cropSource, validateName: validator)
        cropPresenter.setLoopOn(enabled: false)
        cropPresenter.setCropEnd(value: 32)
        crop.expect(cropPresenter.processed.size == 32, message: "A035 crop end trims one-shot render")
        cropPresenter.setNormalizeMode(index: 2)
        crop.expect(
            cropPresenter.params.normalizeMode == .oneShot && cropPresenter.processed.normalizeGain != 1,
            message: "A036 normalize mode applies gain to render")

        let hiRes = try SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav")
        let undoPresenter = SampleStudioPresenter(source: hiRes, validateName: validator)
        let undo = report.scoped(cppID: "samplecheck/SampleProcessingTest::editorUndo")
        undo.expect(hiRes.frameCount == 12_000 && hiRes.hasLoop, message: "A091 undo source imports")
        undoPresenter.setBaseKeyText(text: "A3")
        undo.expect(
            undoPresenter.canUndo && undoPresenter.baseKey == 57, message: "A093 key edit creates an undo entry")
        undoPresenter.undo()
        undo.expect(
            undoPresenter.params == SampleDocument.defaultParams(for: hiRes),
            message: "A094 full undo restores import defaults")
        undoPresenter.redo()
        undo.expect(undoPresenter.baseKey == 57, message: "A095 full redo restores edited state")

        let commit = report.scoped(cppID: "samplecheck/SampleProcessingTest::editorCommit")
        let commitSource = try SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav")
        commit.expect(
            commitSource.frameCount == 12_000 && commitSource.sampleRate == 44_100,
            message: "A108 commit source imports")
        let commitPresenter = SampleStudioPresenter(source: commitSource, validateName: validator)
        commitPresenter.setBaseKeyText(text: "A3")
        commit.expect(
            commitPresenter.params.baseKey == 57 && commitPresenter.params.exactPitchOverride == 0,
            message: "A110 commit preserves edited render parameters")
        commitPresenter.setSampleName(name: "phase3_tone")
        let incPath = root + "/sound/direct_sound_data.inc"
        let incBefore = try Data(contentsOf: URL(filePath: incPath))
        let committedWav = commitPresenter.wavBytes()
        let registrationResult = Result {
            try SampleRegistrar.register(projectRoot: root, name: commitPresenter.sampleName, wav: committedWav)
        }
        guard case .success = registrationResult else {
            report.scoped(cppID: "swiftcore/SampleStudioPresenter::fixture").expect(
                false,
                message: "editor commit registration refused")
            return
        }
        let registeredWav = try Data(contentsOf: URL(filePath: root + "/sound/direct_sound_samples/phase3_tone.wav"))
        commit.expect(registeredWav == committedWav, message: "A111 editor WAV registers")
        let incAfter = try Data(contentsOf: URL(filePath: incPath))
        let block =
            "\n\t.align 2\nDirectSoundWaveData_phase3_tone::\n\t.incbin \"sound/direct_sound_samples/phase3_tone.bin\"\n"
        commit.expect(
            incAfter == incBefore + Data(block.utf8), message: "A112 commit appends exactly registration block")
        let voicePath = root + "/sound/voicegroups/voicegroup_phase3.inc"
        try FileManager.default.createDirectory(
            at: URL(filePath: voicePath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(
            "voicegroup_phase3::\n\tvoice_directsound 60, 0, DirectSoundWaveData_phase3_tone, 255, 0, 255, 165\n".utf8
        )
        .write(to: URL(filePath: voicePath))
        let loaded = root.withCString { path in "voicegroup_phase3".withCString { voicegroup_load(path, $0, nil) } }
        commit.expect(loaded != nil, message: "A114 phase-3 voicegroup resolves")
        if let loaded {
            defer { voicegroup_free(loaded) }
            let output = commitPresenter.processed
            if let wave = loaded.pointee.voices.0.wav, let data = wave.pointee.data {
                let bytes = UnsafeBufferPointer(start: data, count: Int(output.size))
                commit.expect(
                    wave.pointee.freq == output.freq && wave.pointee.loopStart == output.loopStart
                        && wave.pointee.size == output.size && wave.pointee.status == (output.looped ? 0x4000 : 0)
                        && zip(bytes, output.s8).allSatisfy { $0.0 == $0.1 },
                    message: "A115 committed sample loads back identical")
            } else {
                report.scoped(cppID: "swiftcore/SampleStudioPresenter::fixture").expect(
                    false,
                    message: "committed wave has no sample data")
            }
        }

        let edit = report.scoped(cppID: "samplecheck/SampleProcessingTest::sidecarEditDialog")
        let editSource = try SampleImport.decode(hiResSampleWav(), sourcePath: "fix/hires_tone.wav")
        edit.expect(
            editSource.frameCount == 12_000 && editSource.sampleRate == 44_100,
            message: "A060 edit source imports")
        let editPresenter = SampleStudioPresenter(source: editSource, validateName: validator)
        editPresenter.setEditTarget(name: "provenance_tone")
        var baseline = SampleDocument.defaultParams(for: editSource)
        baseline.cropStart = 150
        baseline.targetRate = 13379
        baseline.baseKey = 59
        baseline.fineTuneCents = 25
        editPresenter.applyParamsExternal(baseline)
        edit.expect(
            editPresenter.nameReadOnly && editPresenter.sampleName == "provenance_tone",
            message: "A061 edit mode locks the name")
        edit.expect(
            editPresenter.canCommit && editPresenter.commitLabel == "Save Sample",
            message: "A062 edit mode exposes an enabled commit action")
        edit.expect(
            editPresenter.params == baseline && !editPresenter.canUndo,
            message: "A064 restored provenance params are baseline not undo entry")
        let state = report.scoped(cppID: "swiftcore/SampleStudioPresenter::historyAndReadouts")
        let gesture = SampleStudioPresenter(source: hiRes, validateName: validator)
        var observed: [Int] = []
        gesture.addRenderObserver { observed.append(1) }
        gesture.addRenderObserver { observed.append(2) }
        gesture.setCropStart(value: 100)
        gesture.setCropStart(value: 200)
        state.expect(observed == [1, 2, 1, 2], message: "render observers notify in registration order")
        gesture.undo()
        state.expect(
            gesture.cropStart == 0 && !gesture.canUndo && gesture.canRedo,
            message: "repeated crop edits merge to one reversible gesture")
        gesture.redo()
        state.expect(gesture.cropStart == 200, message: "redo restores merged crop result")
        gesture.beginMarkerGesture()
        gesture.dragMarkers(
            cropStart: 250, cropEnd: gesture.cropEnd, loopStart: gesture.loopStart, loopEnd: gesture.loopEnd)
        gesture.dragMarkers(
            cropStart: 300, cropEnd: gesture.cropEnd, loopStart: gesture.loopStart, loopEnd: gesture.loopEnd)
        gesture.endMarkerGesture()
        gesture.undo()
        state.expect(gesture.cropStart == 200, message: "marker drag reverts to pre-gesture render")
        state.expect(
            gesture.outputSummary.contains("ROM") && gesture.techDetail.contains("agbp"),
            message: "editor readouts report ROM and rendered pitch")
        state.expect(
            defaultPresenter.sourceLine == "8-bit PCM WAV, 1 channel, 13240.09 Hz, 64 samples (0.00 s)"
                && defaultPresenter.rateChoices[0] == "Keep source (13240.09 Hz)",
            message: "source and keep-rate labels reproduce fork PCM text")
        var floatStereo = hiRes
        floatStereo.sourceChannels = 2
        floatStereo.sourceBits = 32
        floatStereo.sourceFloat = true
        floatStereo.sampleRate = 44100.25
        state.expect(
            SampleStudioReadouts.sourceLine(floatStereo)
                == "32-bit float WAV, 2 channels, 44100.25 Hz, 12000 samples (0.27 s)",
            message: "floating stereo source uses fractional rate and plural channels")
        state.expect(
            gesture.normalizeChoices == ["Auto", "Looped (−9 dBFS loop RMS)", "One-shot (peak)", "Off"],
            message: "normalize choices reproduce fork labels")
        let expectedRates: [String] = [
            "5734", "7884", "10512", "13379", "15768", "18157",
            "21024", "26758", "31536", "36314", "40137", "42048",
        ]
        let rateChoicesMatch: Bool = Array(gesture.rateChoices.dropFirst()) == expectedRates
        state.expect(
            rateChoicesMatch,
            message: "rate presets reproduce fork kGbaMixRates ordering")
        var formatted = ProcessedSample()
        formatted.size = 1520
        formatted.outputRate = 1000
        formatted.declaredRate = 1000
        formatted.freq = 225_280
        formatted.normalizeGain = 2
        formatted.seam.valid = true
        formatted.seam.ampLsb = 2
        formatted.seam.derivLsb = 3
        formatted.seam.nccValid = true
        formatted.seam.ncc = 0.987
        formatted.warnings = ["render notice"]
        var warned = defaultSource
        warned.warnings = ["decode notice"]
        state.expect(
            SampleStudioReadouts.summary(source: warned, output: formatted)
                == "1.52 s · 1.5 KB ROM\nWarning: decode notice\nWarning: render notice",
            message: "ROM summary rounds KB to one decimal and retains warning order")
        state.expect(
            SampleStudioReadouts.technical(formatted)
                == "Output: 1520 samples @ 1000 Hz — one-shot\nPitch: 220.00 Hz at C4 (60) — agbp 225280, unity 60 (C4)\nROM cost: 1536 bytes — seam amp 2 LSB, slope 3, match 98%",
            message: "technical readout truncates seam match to integer percent")
        state.expect(
            SampleStudioReadouts.gain(formatted, mode: .oneShot) == "gain 6.0 dB"
                && SampleStudioReadouts.gain(formatted, mode: .off) == "gain 0.0 dB",
            message: "gain readout formats enabled and disabled modes")
        let parsed = SampleStudioPresenter(source: hiRes, validateName: validator)
        parsed.setBaseKeyText(text: "A3 (57)")
        state.expect(parsed.baseKey == 57, message: "display-form note parses back to its MIDI key")
        parsed.setBaseKeyText(text: "C9999")
        state.expect(parsed.baseKey == 127, message: "out-of-range note clamps to MIDI high end")
        parsed.setBaseKeyText(text: "C-9999")
        state.expect(parsed.baseKey == 0, message: "out-of-range negative octave clamps to MIDI low end")
        let returning = SampleStudioPresenter(source: hiRes, validateName: validator)
        let baselineBytes = returning.wavBytes()
        returning.setFineTuneCents(value: 10)
        returning.setFineTuneCents(value: returning.source.fracSemitone * 100)
        state.expect(
            !returning.canUndo && returning.wavBytes() == baselineBytes,
            message: "merged tuning run returning to base drops obsolete undo entry")
    } catch {
        report.scoped(cppID: "swiftcore/SampleStudioPresenter::fixture").expect(
            false, message: "presenter fixture failed: \(error)")
    }
}
