import Foundation
import PorydawProject

internal func runVoicegroupValueSuite(_ report: CheckReport) {
    checkVoicegroupMacroTables(report)
    checkVoicegroupAdsr(report)
    checkVoicegroupStructuralChanges(report)
    checkVoicegroupSynths(report)
}

private func checkVoicegroupMacroTables(_ report: CheckReport) {
    let cppID = "swiftproject/VoicegroupValueChecks::macroTables"
    // Ordinals follow VgMacro's C++ declaration, not the loader's macro dispatch order.
    let rows: [(VgMacro, Int32, String, String, UInt8, Bool, Bool, Int)] = [
        (.directSound, 0, "voice_directsound", "Sample", 0x00, true, false, 0),
        (.directSoundNoResample, 1, "voice_directsound_no_resample", "Sample (fixed pitch)", 0x08, true, false, 0),
        (.directSoundAlt, 2, "voice_directsound_alt", "Sample (reverse)", 0x10, true, false, 0),
        (.square1, 3, "voice_square_1", "Square 1", 0x01, false, true, 3),
        (.square1Alt, 4, "voice_square_1_alt", "Square 1 (alt)", 0x09, false, true, 3),
        (.square2, 5, "voice_square_2", "Square 2", 0x02, false, true, 5),
        (.square2Alt, 6, "voice_square_2_alt", "Square 2 (alt)", 0x0A, false, true, 5),
        (.progWave, 7, "voice_programmable_wave", "Wave", 0x03, true, true, 7),
        (.progWaveAlt, 8, "voice_programmable_wave_alt", "Wave (alt)", 0x0B, true, true, 7),
        (.noise, 9, "voice_noise", "Noise", 0x04, false, true, 9),
        (.noiseAlt, 10, "voice_noise_alt", "Noise (alt)", 0x0C, false, true, 9),
        (.keysplit, 11, "voice_keysplit", "Keysplit", 0x40, true, false, -1),
        (.keysplitAll, 12, "voice_keysplit_all", "Drumkit", 0x80, true, false, -1),
    ]
    report.expectEqual(expected: 13, actual: VgMacro.allCases.count, cppID: cppID,
                       what: "V001: the editable macro set has exactly thirteen entries")
    for (macro, ordinal, name, displayName, voiceType, hasSymbol, isCgb, family) in rows {
        let id = String(format: "V%03d", Int(ordinal) + 2)
        report.expectEqual(expected: ordinal, actual: macro.rawValue, cppID: cppID, what: "\(id): macro ordinal")
        report.expectEqual(expected: name, actual: vgMacroName(macro), cppID: cppID, what: "\(id): assembler macro word")
        report.expectEqual(expected: displayName, actual: vgMacroDisplayName(macro), cppID: cppID,
                           what: "\(id): display label")
        report.expectEqual(expected: voiceType, actual: vgMacroVoiceType(macro), cppID: cppID,
                           what: "\(id): native VOICE_* flag")
        report.expectEqual(expected: hasSymbol, actual: vgMacroHasSymbol(macro), cppID: cppID,
                           what: "\(id): requires a symbol argument")
        report.expectEqual(expected: isCgb, actual: vgMacroIsCgb(macro), cppID: cppID,
                           what: "\(id): uses CGB envelope scale")
        report.expectEqual(expected: family, actual: vgAdsrFamily(macro), cppID: cppID,
                           what: "\(id): envelope family collapse")
    }
    let lineKinds: [(VgLineKind, Int32)] = [
        (.none, 0), (.other, 1), (.header, 2), (.editable, 3),
        (.readOnlyVoice, 4), (.broken, 5),
    ]
    for (kind, ordinal) in lineKinds {
        report.expectEqual(expected: ordinal, actual: kind.rawValue, cppID: cppID,
                           what: "V\(String(format: "%03d", 15 + Int(ordinal))): source line kind ordinal")
    }
}

private func checkVoicegroupAdsr(_ report: CheckReport) {
    let cppID = "swiftproject/VoicegroupValueChecks::defaultAdsr"
    let symbolEnvelope = VgAdsr(attack: 4, decay: 5, sustain: 6, release: 7)
    let familyEnvelope = VgAdsr(attack: 1, decay: 2, sustain: 3, release: 4)
    let directFallback = VgAdsr(attack: 255, decay: 0, sustain: 255, release: 165)
    let cgbFallback = VgAdsr(attack: 0, decay: 0, sustain: 15, release: 3)
    let defaults = VgAdsrDefaults(bySymbol: ["sample": symbolEnvelope, "": symbolEnvelope],
                                  byFamily: [0: familyEnvelope, 3: familyEnvelope, -1: familyEnvelope])
    report.expectEqual(expected: symbolEnvelope, actual: vgDefaultAdsr(defaults, .directSoundAlt, "sample"),
                       cppID: cppID, what: "V021: symbol override precedes direct-sound family")
    report.expectEqual(expected: symbolEnvelope, actual: vgDefaultAdsr(defaults, .square1Alt, "sample"),
                       cppID: cppID, what: "V022: symbol override precedes CGB family")
    report.expectEqual(expected: familyEnvelope, actual: vgDefaultAdsr(defaults, .directSoundNoResample, "missing"),
                       cppID: cppID, what: "V023: variant uses its base family when symbol misses")
    report.expectEqual(expected: familyEnvelope, actual: vgDefaultAdsr(defaults, .square1Alt, ""),
                       cppID: cppID, what: "V024: empty symbol selects family")
    report.expectEqual(expected: familyEnvelope, actual: vgDefaultAdsr(defaults, .keysplit, "missing"),
                       cppID: cppID, what: "V025: no-envelope family still consults the -1 entry")
    report.expectEqual(expected: directFallback, actual: vgDefaultAdsr(VgAdsrDefaults(), .directSound, ""),
                       cppID: cppID, what: "V026: direct sound falls back to sustained 8-bit envelope")
    report.expectEqual(expected: directFallback, actual: vgDefaultAdsr(VgAdsrDefaults(), .keysplitAll, ""),
                       cppID: cppID, what: "V027: drumkit uses non-CGB fallback")
    for macro in [VgMacro.square1, .square2Alt, .progWave, .noiseAlt] {
        report.expectEqual(expected: cgbFallback, actual: vgDefaultAdsr(VgAdsrDefaults(), macro, "missing"),
                           cppID: cppID, what: "V028: \(macro) uses sustained CGB fallback")
    }
    report.expectEqual(expected: familyEnvelope, actual: vgDefaultAdsr(defaults, .square1, "sampleNotPresent"),
                       cppID: cppID, what: "V029: unknown symbol does not hide family")
    report.expectEqual(expected: familyEnvelope, actual: vgDefaultAdsr(defaults, .directSound, ""),
                       cppID: cppID, what: "V030: empty symbol never matches symbol table")
}

private func checkVoicegroupStructuralChanges(_ report: CheckReport) {
    let cppID = "swiftproject/VoicegroupValueChecks::structuralChange"
    let before = VgVoice(macro: .keysplit, key: 60, pan: 1, symbol: "vg_a",
                         keysplitTable: "table_a", sweep: 1, duty: 2, period: 3,
                         attack: 4, decay: 5, sustain: 6, release: 7)
    report.expect(!vgVoiceStructuralChange(before, before), cppID: cppID,
                  message: "V031: identical voices need no structural reload")
    let edits: [(String, Bool, (inout VgVoice) -> Void)] = [
        ("macro", true, { $0.macro = .keysplitAll }),
        ("symbol", true, { $0.symbol = "vg_b" }),
        ("keysplit table", true, { $0.keysplitTable = "table_b" }),
        ("key", false, { $0.key = 61 }),
        ("pan", false, { $0.pan = 2 }),
        ("sweep", false, { $0.sweep = 2 }),
        ("duty", false, { $0.duty = 3 }),
        ("period", false, { $0.period = 4 }),
        ("attack", false, { $0.attack = 5 }),
        ("decay", false, { $0.decay = 6 }),
        ("sustain", false, { $0.sustain = 7 }),
        ("release", false, { $0.release = 8 }),
    ]
    for (index, (label, structural, edit)) in edits.enumerated() {
        var after = before
        edit(&after)
        let id = String(format: "V%03d", 32 + index)
        report.expectEqual(expected: structural, actual: vgVoiceStructuralChange(before, after),
                           cppID: cppID, what: "\(id): \(label) edit structural classification")
        report.expectEqual(expected: structural, actual: vgVoiceStructuralChange(after, before),
                           cppID: cppID, what: "\(id): reverse \(label) edit classification")
    }
}

private func checkVoicegroupSynths(_ report: CheckReport) {
    let cppID = "swiftproject/VoicegroupValueChecks::synth"
    report.expectEqual(expected: "Pulse", actual: vgSynthWaveformName(0), cppID: cppID,
                       what: "V044: pulse waveform label")
    report.expectEqual(expected: "Sawtooth", actual: vgSynthWaveformName(1), cppID: cppID,
                       what: "V045: saw waveform label")
    report.expectEqual(expected: "Triangle", actual: vgSynthWaveformName(2), cppID: cppID,
                       what: "V046: triangle waveform label")
    report.expectEqual(expected: "Triangle", actual: vgSynthWaveformName(-1), cppID: cppID,
                       what: "V047: unknown waveform uses triangle label")
    let pulse = VgSynthDesc()
    report.expectEqual(expected: "DirectSoundSynth_GoldenSun_80000000", actual: vgSynthSymbolName(pulse),
                       cppID: cppID, what: "V048: default pulse symbol contains all four bytes")
    let truncated = VgSynthDesc(baseDuty: 0x1AB, dutyStep: -1, modDepth: 0x100, phase: 0xA0)
    report.expectEqual(expected: "DirectSoundSynth_GoldenSun_ABFF00A0", actual: vgSynthSymbolName(truncated),
                       cppID: cppID, what: "V049: pulse parameters truncate to uppercase hex bytes")
    let saw = VgSynthDesc(waveform: 1)
    let triangle = VgSynthDesc(waveform: 2)
    report.expectEqual(expected: "DirectSoundSynth_GoldenSun_Saw", actual: vgSynthSymbolName(saw),
                       cppID: cppID, what: "V050: saw symbol ignores pulse bytes")
    report.expectEqual(expected: "DirectSoundSynth_GoldenSun_Triangle", actual: vgSynthSymbolName(triangle),
                       cppID: cppID, what: "V051: triangle symbol ignores pulse bytes")
    report.expectEqual(expected: "DirectSoundSynth_GoldenSun_Triangle", actual: vgSynthSymbolName(VgSynthDesc(waveform: 9)),
                       cppID: cppID, what: "V052: unknown waveform uses triangle symbol")
    report.expect(pulse == VgSynthDesc(waveform: 0, baseDuty: 0x80, dutyStep: 0,
                                       modDepth: 0, phase: 0),
                  cppID: cppID, message: "V053: matching pulse fields compare equal")
    let pulseDifferences = [
        VgSynthDesc(baseDuty: 0x81), VgSynthDesc(dutyStep: 1),
        VgSynthDesc(modDepth: 1), VgSynthDesc(phase: 1),
    ]
    for (index, changed) in pulseDifferences.enumerated() {
        report.expect(pulse != changed, cppID: cppID,
                      message: "V\(String(format: "%03d", 54 + index)): pulse parameter \(index) participates in equality")
    }
    let sawOther = VgSynthDesc(waveform: 1, baseDuty: 0x21, dutyStep: 3, modDepth: 4, phase: 5)
    let triangleOther = VgSynthDesc(waveform: 2, baseDuty: 0x21, dutyStep: 3, modDepth: 4, phase: 5)
    report.expect(saw == sawOther, cppID: cppID,
                  message: "V058: saw equality ignores pulse parameters")
    report.expect(triangle == triangleOther, cppID: cppID,
                  message: "V059: triangle equality ignores pulse parameters")
    report.expect(saw != triangle && saw != pulse, cppID: cppID,
                  message: "V060: different waveform kinds never compare equal")
    report.expectEqual(expected: "DirectSoundSynth_GoldenSun_Saw", actual: vgSynthSymbolName(sawOther),
                       cppID: cppID, what: "V061: saw naming ignores nondefault pulse parameters")
    report.expectEqual(expected: "DirectSoundSynth_GoldenSun_Triangle", actual: vgSynthSymbolName(triangleOther),
                       cppID: cppID, what: "V062: triangle naming ignores nondefault pulse parameters")
}
