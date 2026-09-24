import Foundation
import PorydawProject

internal func runSynthCatalogSuite(_ report: CheckReport) {
    synthSoundDataChecks(report)
    synthVoicegroupChecks(report)
    synthStagedFixtureChecks(report)
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
        report.expectEqual(expectedSamples, samples, cppID: cppID,
                           what: "S001: cry and synth labels excluded, duplicates removed, phonemes sorted last")
        report.expectEqual(["ProgrammableWaveData_colon_wave", "ProgrammableWaveData_other"],
                           VoicegroupSource.progWaveSymbols(path), cppID: cppID,
                           what: "S002: single-colon wave labels are deduplicated and sorted, cries excluded")
        let synths = VoicegroupSource.synthInstruments(path)
        report.expectEqual(["SynthCheckInline", "SynthCheckPulse", "SynthCheckSaw",
                            "SynthCheckTriangle", "SynthCheck50"],
                           synths.defs.map(\.symbol), cppID: cppID,
                           what: "S003: synth definitions retain sound-data file order")
        report.expectEqual(VgSynthDesc(waveform: 0, baseDuty: 0x10, dutyStep: 0xF0,
                                       modDepth: 0xE0, phase: 0x80), synths.find("SynthCheckInline"),
                           cppID: cppID, what: "S004: custom pulse descriptor parses hex parameters")
        report.expectEqual(VgSynthDesc(waveform: 1), synths.find("SynthCheckSaw"), cppID: cppID,
                           what: "S005: saw descriptor parses from separate synth-data file")
        report.expectEqual(VgSynthDesc(waveform: 2), synths.find("SynthCheckTriangle"), cppID: cppID,
                           what: "S006: triangle descriptor parses from separate synth-data file")
        report.expectEqual(VgSynthDesc(waveform: 0, baseDuty: 0x20, dutyStep: 0x10,
                                       modDepth: 0x30, phase: 0x40), synths.find("SynthCheckPulse"),
                           cppID: cppID, what: "S006a: pulse alias parses distinct waveform and parameters")
        report.expectEqual(VgSynthDesc(waveform: 2), synths.find("SynthCheck50"), cppID: cppID,
                           what: "S006b: set_synth_50 alias uses triangle waveform")
        report.expectEqual(["set_synth_pulse", "set_synth_saw", "set_synth_triangle", "set_synth_custom"],
                           synths.macroWords, cppID: cppID,
                           what: "S007: defining macro words preserve file order without duplicates")
        report.expect(synths.available() && synths.creatable(), cppID: cppID,
                      message: "S008: definitions with defining macros are available and creatable")
        let fused = VoicegroupSource.directSoundCatalog(path)
        report.expectEqual(samples, fused.directSound, cppID: cppID,
                           what: "S009: fused direct-sound symbols equal standalone scan")
        report.expectEqual(synths.defs.map(\.symbol), fused.synths.defs.map(\.symbol), cppID: cppID,
                           what: "S010: fused synth definition order equals standalone scan")
        report.expectEqual(synths.defs.map(\.descriptor), fused.synths.defs.map(\.descriptor), cppID: cppID,
                           what: "S011: fused synth descriptors equal standalone scan")
        report.expectEqual(synths.macroWords, fused.synths.macroWords, cppID: cppID,
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
        report.expectEqual(["_adsrcheck", "_z_extra"], scan.groupArgs, cppID: cppID,
                           what: "S017: fused voicegroup args retain C++ prefix stripping and sort order")
        let pairs = VoicegroupSource.keysplitInstruments(path)
        let expectedPairs = ["KeyA:TableFirst", "KeyB:TableB", "KeyZ:TableZ"]
        report.expectEqual(expectedPairs, pairs.map { "\($0.symbol):\($0.table)" }, cppID: cppID,
                           what: "S018: keysplit pairs are sorted by symbol and first definition wins")
        report.expectEqual(expectedPairs, scan.keysplits.map { "\($0.symbol):\($0.table)" }, cppID: cppID,
                           what: "S019: fused keysplit pairs equal standalone accessor")
        let drums = VoicegroupSource.drumkitInstruments(path)
        report.expectEqual(["DrumA", "DrumB", "DrumZ"], drums, cppID: cppID,
                           what: "S020: drumkit symbols are deduplicated and sorted")
        report.expectEqual(drums, scan.drumkits, cppID: cppID,
                           what: "S021: fused drumkits equal standalone accessor")
        let defaults = VoicegroupSource.typicalAdsr(path)
        report.expectEqual(VgAdsr(attack: 1, decay: 2, sustain: 10, release: 3),
                           defaults.byFamily[vgAdsrFamily(.square1)], cppID: cppID,
                           what: "S022: release-zero filler squares do not outrank audible square envelope")
        report.expectEqual(VgAdsr(attack: 1, decay: 2, sustain: 4, release: 3),
                           defaults.byFamily[vgAdsrFamily(.square2Alt)], cppID: cppID,
                           what: "S023: tied envelope frequencies select smaller packed mode code")
        report.expectEqual(VgAdsr(attack: 255, decay: 0, sustain: 255, release: 165),
                           defaults.byFamily[vgAdsrFamily(.directSoundNoResample)], cppID: cppID,
                           what: "S024: DirectSound attack-zero is skipped and variants share a family")
        report.expectEqual(VgAdsr(attack: 255, decay: 0, sustain: 255, release: 165),
                           defaults.bySymbol["AdsrCheckA"], cppID: cppID,
                           what: "S025: most frequent audible per-symbol DirectSound envelope wins")
        report.expect(defaults.bySymbol["AdsrCheckB"] == nil, cppID: cppID,
                      message: "S026: DirectSound attack-zero symbol has no suggested envelope")
        report.expect(defaults.bySymbol["AdsrCheckC"] == nil, cppID: cppID,
                      message: "S026a: release-zero DirectSound symbol has no suggested envelope")
        report.expectEqual(VgAdsr(attack: 1, decay: 0, sustain: 13, release: 2),
                           defaults.byFamily[vgAdsrFamily(.noise)], cppID: cppID,
                           what: "S027: audible noise family remains available")
        report.expectEqual(defaults.byFamily, scan.typicalAdsr.byFamily, cppID: cppID,
                           what: "S028: fused ADSR family defaults equal standalone scan")
        report.expectEqual(defaults.bySymbol, scan.typicalAdsr.bySymbol, cppID: cppID,
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
    report.expectEqual(["DirectSoundWaveData_fixture_bass", "DirectSoundWaveData_fixture_drum",
                        "DirectSoundWaveData_fixture_loop", "DirectSoundWaveData_fixture_pluck"],
                       VoicegroupSource.directSoundSymbols(root), cppID: cppID,
                       what: "S033: staged decomp DirectSound symbol order matches fixture")
    report.expectEqual(["ProgrammableWaveData_fixture_pulse", "ProgrammableWaveData_fixture_saw"],
                       VoicegroupSource.progWaveSymbols(root), cppID: cppID,
                       what: "S034: staged decomp programmable wave symbols match fixture")
}

private func synthWrite(_ root: URL, _ relativePath: String, _ contents: String) throws {
    let file = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: file)
}
