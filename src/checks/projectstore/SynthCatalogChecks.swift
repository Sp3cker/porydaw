import Foundation
import PorydawProject
import PorydawProjectNative

internal func runSynthCatalogSuite(_ report: CheckReport) {
    synthSoundDataChecks(report)
    synthVoicegroupChecks(report)
    synthStagedFixtureChecks(report)
    synthFixtureAdsrChecks(report)
    synthSingleColonLoadChecks(report)
}

private func synthSoundDataChecks(_ report: CheckReport) {
    let cppID = "swiftproject/SynthCatalogChecks::soundData"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "synth-sound-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        try synthWrite(root, "sound/direct_sound_data.inc", """
            DirectSoundWaveData_colon_double::
            \t.incbin "sound/direct_sound_samples/colon_double.bin"
            DirectSoundWaveData_colon_single:
            \t.incbin "sound/direct_sound_samples/colon_single.bin"
            DirectSoundWaveData_Phoneme_z::
            \t.incbin "sound/direct_sound_samples/phoneme.bin"
            DirectSoundWaveData_Phoneme_a:
            \t.incbin "sound/direct_sound_samples/phoneme_a.bin"
            CryExcluded::
            \t.incbin "sound/direct_sound_samples/cries/cry.bin"
            SynthCheckInline:: @ Golden Sun pulse
            \tset_synth_custom 0x10, 0xF0, 0xE0, 0x80
            SynthCheckPulse::
            \tset_synth_pulse 0x20, 0x10, 0x30, 0x40
            DirectSoundWaveData_colon_single:
            \t.incbin "sound/direct_sound_samples/colon_single.bin"
            """)
        try synthWrite(root, "sound/direct_sound_synth_data.inc", """
            \t.align 2\r
            SynthCheckSaw::\r
                set_synth_25\r
            SynthCheckTriangle:\r
                set_synth_triangle\r
            SynthCheck50::\r
                set_synth_50\r
            """)
        try synthWrite(root, "asm/macros/music_voice.inc", """
            \t.macro set_synth_pulse a=0, b=0, c=0, d=0
            \t.endm
            \t.macro set_synth_saw
            \t.endm
            \t.macro set_synth_triangle
            \t.endm
            \t.macro set_synth_custom a:req, b:req, c:req, d:req
            \t.endm
            \t.macro set_synth_saw
            \t.endm
            """)
        try synthWrite(root, "sound/programmable_wave_data.inc", """
            ProgrammableWaveData_colon_wave:
            \t.incbin "sound/programmable_wave_samples/colon_wave.pcm"
            ProgrammableWaveData_other::
            \t.incbin "sound/programmable_wave_samples/other.pcm"
            ProgrammableWaveData_colon_wave:
            \t.incbin "sound/programmable_wave_samples/colon_wave.pcm"
            CryWave::
            \t.incbin "sound/programmable_wave_samples/cries/cry.pcm"
            """)

        let path = root.path
        let expectedSamples = ["DirectSoundWaveData_colon_double", "DirectSoundWaveData_colon_single",
                               "DirectSoundWaveData_Phoneme_a", "DirectSoundWaveData_Phoneme_z"]
        let samples = VoicegroupSource.directSoundSymbols(path)
        report.expectEqual(expected: expectedSamples, actual: samples, cppID: cppID,
                           what: "S001: cry and synth labels excluded, duplicates removed, phonemes sorted last")
        report.expectEqual(expected: ["ProgrammableWaveData_colon_wave", "ProgrammableWaveData_other"],
                           actual: VoicegroupSource.progWaveSymbols(path), cppID: cppID,
                           what: "S002: single-colon wave labels are deduplicated and sorted, cries excluded")
        let synths = VoicegroupSource.synthInstruments(path)
        report.expectEqual(expected: ["SynthCheckInline", "SynthCheckPulse", "SynthCheckSaw",
                            "SynthCheckTriangle", "SynthCheck50"],
                           actual: synths.defs.map(\.symbol), cppID: cppID,
                           what: "S003: synth definitions retain sound-data file order")
        report.expectEqual(expected: VgSynthDesc(waveform: 0, baseDuty: 0x10, dutyStep: 0xF0,
                                       modDepth: 0xE0, phase: 0x80), actual: synths.find("SynthCheckInline"),
                           cppID: cppID, what: "S004: custom pulse descriptor parses hex parameters")
        report.expectEqual(expected: "SynthCheckInline",
                           actual: synths.symbolFor(VgSynthDesc(waveform: 0, baseDuty: 0x10,
                                                                dutyStep: 0xF0, modDepth: 0xE0, phase: 0x80)),
                           cppID: cppID, what: "a pulse descriptor resolves its original synth symbol")
        report.expectEqual(expected: VgSynthDesc(waveform: 1), actual: synths.find("SynthCheckSaw"), cppID: cppID,
                           what: "S005: saw descriptor parses from separate synth-data file")
        report.expectEqual(expected: "SynthCheckSaw", actual: synths.symbolFor(VgSynthDesc(waveform: 1)),
                           cppID: cppID, what: "a saw descriptor resolves its original synth symbol")
        report.expectEqual(expected: VgSynthDesc(waveform: 2), actual: synths.find("SynthCheckTriangle"), cppID: cppID,
                           what: "S006: triangle descriptor parses from separate synth-data file")
        report.expectEqual(expected: VgSynthDesc(waveform: 0, baseDuty: 0x20, dutyStep: 0x10,
                                       modDepth: 0x30, phase: 0x40), actual: synths.find("SynthCheckPulse"),
                           cppID: cppID, what: "S006a: pulse alias parses distinct waveform and parameters")
        report.expectEqual(expected: VgSynthDesc(waveform: 2), actual: synths.find("SynthCheck50"), cppID: cppID,
                           what: "S006b: set_synth_50 alias uses triangle waveform")
        report.expectEqual(expected: ["set_synth_pulse", "set_synth_saw", "set_synth_triangle", "set_synth_custom"],
                           actual: synths.macroWords, cppID: cppID,
                           what: "S007: defining macro words preserve file order without duplicates")
        report.expect(synths.available() && synths.creatable(), cppID: cppID,
                      message: "S008: definitions with defining macros are available and creatable")
        let fused = VoicegroupSource.directSoundCatalog(path)
        report.expectEqual(expected: samples, actual: fused.directSound, cppID: cppID,
                           what: "S009: fused direct-sound symbols equal standalone scan")
        report.expectEqual(expected: synths.defs.map(\.symbol), actual: fused.synths.defs.map(\.symbol), cppID: cppID,
                           what: "S010: fused synth definition order equals standalone scan")
        report.expectEqual(expected: synths.defs.map(\.descriptor), actual: fused.synths.defs.map(\.descriptor), cppID: cppID,
                           what: "S011: fused synth descriptors equal standalone scan")
        report.expectEqual(expected: synths.macroWords, actual: fused.synths.macroWords, cppID: cppID,
                           what: "S012: fused defining macro words equal standalone scan")

        try FileManager.default.removeItem(at: root.appendingPathComponent("asm/macros/music_voice.inc"))
        let definitionsOnly = VoicegroupSource.synthInstruments(path)
        report.expect(definitionsOnly.available() && !definitionsOnly.creatable(), cppID: cppID,
                      message: "S013: existing definitions without defining macros cannot create new synths")
        try FileManager.default.removeItem(at: root.appendingPathComponent("sound/direct_sound_data.inc"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("sound/direct_sound_synth_data.inc"))
        report.expect(!VoicegroupSource.synthInstruments(path).available(), cppID: cppID,
                      message: "S014: absent definitions and macros are unavailable")
        try synthWrite(root, "asm/macros/music_voice.inc", "\t.macro set_synth_saw\n\t.endm\n")
        let macrosOnly = VoicegroupSource.synthInstruments(path)
        report.expect(macrosOnly.defs.isEmpty && macrosOnly.available() && macrosOnly.creatable(),
                      cppID: cppID, message: "S015: defining macros alone enable availability and creation")
    } catch {
        report.fail(cppID, "S016: sound-data fixture operation failed: \(error)")
    }
}

private func synthVoicegroupChecks(_ report: CheckReport) {
    let cppID = "swiftproject/SynthCatalogChecks::voicegroups"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "synth-groups-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        try synthWrite(root, "sound/voicegroups/adsrcheck.inc", """
            voicegroup_adsrcheck::
            \tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0
            \tvoice_square_1 60, 0, 0, 2, 1, 2, 10, 3
            \tvoice_square_1 60, 0, 0, 2, 1, 2, 10, 3
            \tvoice_square_1 60, 0, 0, 2, 2, 0, 12, 1
            \tvoice_square_2 60, 0, 2, 2, 2, 4, 3
            \tvoice_square_2_alt 60, 0, 2, 1, 2, 4, 3
            \tvoice_directsound 60, 0, AdsrCheckA, 255, 0, 255, 165
            \tvoice_directsound_no_resample 60, 0, AdsrCheckA, 255, 0, 255, 165
            \tvoice_directsound 60, 0, AdsrCheckA, 200, 100, 128, 216
            \tvoice_directsound 60, 0, AdsrCheckB, 0, 0, 255, 165
            \tvoice_directsound 60, 0, AdsrCheckC, 255, 0, 255, 0
            \tvoice_directsound\t60, 0, TabSkipped, 255, 0, 255, 165
            \tvoice_noise 60, 0, 0, 1, 0, 13, 2
            \tvoice_keysplit KeyA, TableFirst
            \tvoice_keysplit KeyA, TableIgnored
            \tvoice_keysplit KeyZ, TableZ
            \tvoice_keysplit_all DrumZ
            \tvoice_keysplit_all DrumA
            \tvoice_keysplit_all DrumZ
            """)
        try synthWrite(root, "sound/voicegroups/z_extra.inc", """
            voicegroup_z_extra::
            \tvoice_keysplit KeyA, TableTooLate
            \tvoice_keysplit KeyB, TableB
            \tvoice_keysplit_all DrumB
            """)
        let path = root.path
        let scan = VoicegroupSource.catalogScan(path)
        report.expectEqual(expected: ["_adsrcheck", "_z_extra"], actual: scan.groupArgs, cppID: cppID,
                           what: "S017: fused voicegroup args retain C++ prefix stripping and sort order")
        let pairs = VoicegroupSource.keysplitInstruments(path)
        let expectedPairs = ["KeyA:TableFirst", "KeyB:TableB", "KeyZ:TableZ"]
        report.expectEqual(expected: expectedPairs, actual: pairs.map { "\($0.symbol):\($0.table)" }, cppID: cppID,
                           what: "S018: keysplit pairs are sorted by symbol and first definition wins")
        report.expectEqual(expected: expectedPairs, actual: scan.keysplits.map { "\($0.symbol):\($0.table)" }, cppID: cppID,
                           what: "S019: fused keysplit pairs equal standalone accessor")
        let drums = VoicegroupSource.drumkitInstruments(path)
        report.expectEqual(expected: ["DrumA", "DrumB", "DrumZ"], actual: drums, cppID: cppID,
                           what: "S020: drumkit symbols are deduplicated and sorted")
        report.expectEqual(expected: drums, actual: scan.drumkits, cppID: cppID,
                           what: "S021: fused drumkits equal standalone accessor")
        let defaults = VoicegroupSource.typicalAdsr(path)
        report.expectEqual(expected: VgAdsr(attack: 1, decay: 2, sustain: 10, release: 3),
                           actual: defaults.byFamily[vgAdsrFamily(.square1)], cppID: cppID,
                           what: "S022: release-zero filler squares do not outrank audible square envelope")
        report.expectEqual(expected: VgAdsr(attack: 1, decay: 2, sustain: 4, release: 3),
                           actual: defaults.byFamily[vgAdsrFamily(.square2Alt)], cppID: cppID,
                           what: "S023: tied envelope frequencies select smaller packed mode code")
        report.expectEqual(expected: VgAdsr(attack: 255, decay: 0, sustain: 255, release: 165),
                           actual: defaults.byFamily[vgAdsrFamily(.directSoundNoResample)], cppID: cppID,
                           what: "S024: DirectSound attack-zero is skipped and variants share a family")
        report.expectEqual(expected: VgAdsr(attack: 255, decay: 0, sustain: 255, release: 165),
                           actual: defaults.bySymbol["AdsrCheckA"], cppID: cppID,
                           what: "S025: most frequent audible per-symbol DirectSound envelope wins")
        report.expect(defaults.bySymbol["AdsrCheckB"] == nil, cppID: cppID,
                      message: "S026: DirectSound attack-zero symbol has no suggested envelope")
        report.expect(defaults.bySymbol["AdsrCheckC"] == nil, cppID: cppID,
                      message: "S026a: release-zero DirectSound symbol has no suggested envelope")
        report.expectEqual(expected: VgAdsr(attack: 1, decay: 0, sustain: 13, release: 2),
                           actual: defaults.byFamily[vgAdsrFamily(.noise)], cppID: cppID,
                           what: "S027: audible noise family remains available")
        report.expectEqual(expected: defaults.byFamily, actual: scan.typicalAdsr.byFamily, cppID: cppID,
                           what: "S028: fused ADSR family defaults equal standalone scan")
        report.expectEqual(expected: defaults.bySymbol, actual: scan.typicalAdsr.bySymbol, cppID: cppID,
                           what: "S029: fused ADSR per-symbol defaults equal standalone scan")
        report.expect(defaults.bySymbol["TabSkipped"] == nil, cppID: cppID,
                      message: "S029a: macro followed by tab is not an ADSR voice line")
    } catch {
        report.fail(cppID, "S030: voicegroup fixture operation failed: \(error)")
    }
}

private func synthStagedFixtureChecks(_ report: CheckReport) {
    let cppID = "swiftproject/SynthCatalogChecks::stagedFixture"
    guard let soundPath = CheckEnvironment.fixturePath("sound/direct_sound_data.inc"),
          let wavePath = CheckEnvironment.fixturePath("sound/programmable_wave_data.inc") else {
        report.fail(cppID, "S031: staged decomp fixture root is missing")
        return
    }
    let root = URL(fileURLWithPath: soundPath).deletingLastPathComponent().deletingLastPathComponent().path
    report.expect(FileManager.default.fileExists(atPath: soundPath) &&
                      FileManager.default.fileExists(atPath: wavePath), cppID: cppID,
                  message: "S032: staged decomp sound-data files exist")
    report.expectEqual(expected: ["DirectSoundWaveData_fixture_bass", "DirectSoundWaveData_fixture_drum",
                        "DirectSoundWaveData_fixture_loop", "DirectSoundWaveData_fixture_pluck"],
                       actual: VoicegroupSource.directSoundSymbols(root), cppID: cppID,
                       what: "S033: staged decomp DirectSound symbol order matches fixture")
    report.expectEqual(expected: ["ProgrammableWaveData_fixture_pulse", "ProgrammableWaveData_fixture_saw"],
                       actual: VoicegroupSource.progWaveSymbols(root), cppID: cppID,
                       what: "S034: staged decomp programmable wave symbols match fixture")
}

private func synthFixtureAdsrChecks(_ report: CheckReport) {
    let cppID = "swiftproject/SynthCatalogChecks::fixtureAdsr"
    guard let fixture = CheckEnvironment.fixtureRoot else {
        report.fail(cppID, "staged decomp fixture root is missing")
        return
    }
    let defaults = VoicegroupSource.typicalAdsr(fixture)
    let directSound = vgAdsrFamily(.directSound)
    report.expect(!defaults.byFamily.isEmpty && defaults.byFamily.allSatisfy { family, adsr in
        let chip = family != directSound
        let max = chip ? 7 : 255
        return adsr.release > 0 && adsr.release <= max &&
            adsr.attack >= 0 && adsr.attack <= max && (!chip || adsr.attack > 0) &&
            adsr.decay >= 0 && adsr.decay <= max &&
            adsr.sustain >= 0 && adsr.sustain <= (chip ? 15 : 255)
    }, cppID: cppID, message: "fixture family defaults are audible and chip-bounded")
    report.expect(!defaults.bySymbol.isEmpty && defaults.bySymbol.values.allSatisfy { adsr in
        adsr.release > 0 && adsr.release <= 255 && adsr.attack >= 0 && adsr.attack <= 255 &&
            adsr.decay >= 0 && adsr.decay <= 255 && adsr.sustain >= 0 && adsr.sustain <= 255
    }, cppID: cppID, message: "fixture symbol defaults are audible and bounded")
}

private func synthSingleColonLoadChecks(_ report: CheckReport) {
    let cppID = "swiftproject/SynthCatalogChecks::singleColonLoad"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "synth-colon-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        let single = "sound/direct_sound_samples/colon_single.bin"
        let double = "sound/direct_sound_samples/colon_double.bin"
        let wave = "sound/programmable_wave_samples/colon_wave.pcm"
        for (path, value) in [(single, UInt8(0x11)), (double, UInt8(0x22))] {
            var bytes = [UInt8](repeating: 0, count: 20)
            bytes[12] = 4
            bytes.replaceSubrange(16..<20, with: repeatElement(value, count: 4))
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(bytes).write(to: file)
        }
        let waveFile = root.appendingPathComponent(wave)
        try FileManager.default.createDirectory(at: waveFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x33, count: 16).write(to: waveFile)
        try synthWrite(root, "sound/direct_sound_data.inc", """
            DirectSoundWaveData_colon_double::
            \t.incbin "\(double)"
            DirectSoundWaveData_colon_single:
            \t.incbin "\(single)"
            ColonCheckSynth:
            \tset_synth_25
            """)
        try synthWrite(root, "sound/programmable_wave_data.inc", """
            ProgrammableWaveData_colon_wave:
            \t.incbin "\(wave)"
            """)
        try synthWrite(root, "sound/voicegroups/coloncheck.inc", """
            voicegroup_coloncheck::
            \tvoice_directsound 60, 0, DirectSoundWaveData_colon_single, 255, 0, 255, 165
            \tvoice_directsound 60, 0, DirectSoundWaveData_colon_double, 255, 0, 255, 165
            \tvoice_programmable_wave 60, 0, ProgrammableWaveData_colon_wave, 0, 0, 15, 3
            """)
        let scan = VoicegroupSource.directSoundCatalog(root.path)
        report.expect(scan.directSound.contains("DirectSoundWaveData_colon_single") &&
                      scan.directSound.contains("DirectSoundWaveData_colon_double") &&
                      !scan.directSound.contains("ColonCheckSynth") &&
                      scan.synths.find("ColonCheckSynth") != nil &&
                      VoicegroupSource.progWaveSymbols(root.path).contains("ProgrammableWaveData_colon_wave"),
                      cppID: cppID, message: "single-colon sample labels resolve in both sound-data scans")
        let loaded = root.path.withCString { path in
            "coloncheck".withCString { voicegroup_load(path, $0, nil) }
        }
        guard let loaded else { report.fail(cppID, "single-colon bank did not load"); return }
        defer { voicegroup_free(loaded) }
        let sampleSizes = [0, 1].map { slot -> (UInt32?, UInt8?) in
            let tone = withUnsafePointer(to: &loaded.pointee.voices) {
                $0.withMemoryRebound(to: ToneData.self, capacity: 128) { $0[slot] }
            }
            return (tone.wav?.pointee.size, tone.wav?.pointee.data.map { UInt8(bitPattern: $0[0]) })
        }
        report.expect(sampleSizes[0].0 == 4 && sampleSizes[0].1 == 0x11 &&
                      sampleSizes[1].0 == 4 && sampleSizes[1].1 == 0x22,
                      cppID: cppID, message: "single-colon sample labels load with exact wave bytes")
        let waveTone = withUnsafePointer(to: &loaded.pointee.voices) {
            $0.withMemoryRebound(to: ToneData.self, capacity: 128) { $0[2] }
        }
        report.expect(waveTone.wavePointer != nil, cppID: cppID,
                      message: "programmable wave voices resolve a wave pointer")
    } catch {
        report.fail(cppID, "single-colon fixture failed: \(error)")
    }
}

private func synthWrite(_ root: URL, _ relativePath: String, _ contents: String) throws {
    let file = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: file)
}
