import PorydawAppAudio
import PorydawKitStudio
import PorydawSample
import PorydawVoicegroup

@MainActor
public func runKitDraftSuite(_ report: CheckReport) {
    checkKitDraftHistory(report)
    checkKitDrumkitCodec(report)
    checkKitKeysplitCodec(report)
    checkKitToneCodec(report)
}

private func sampleZone(
    _ start: Int, _ end: Int, name: String = "slice", pitched: Bool = false, pan: Int = 0
) -> KitZone {
    KitZone(
        startKey: start, endKey: end, sampleName: name, rootKey: 60,
        pitched: pitched, pan: pan, adsr: (255, 4, 200, 0))
}

private func lockedZone(_ start: Int, _ end: Int, voice: VgVoice) -> KitZone {
    KitZone(
        startKey: start, endKey: end, sampleName: voice.symbol, rootKey: voice.key,
        pitched: false, pan: 0, adsr: (voice.attack, voice.decay, voice.sustain, voice.release),
        locked: true, lockedVoice: voice)
}

@MainActor
private func checkKitDraftHistory(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitDraft::historyAndInvariants")
    let draft = KitDraft()
    let initial = KitDraft.Snapshot(drumkitZones: [sampleZone(10, 12)], keysplitZones: [sampleZone(0, 127)])
    draft.load(initial)
    r.expect(!draft.dirty && !draft.canUndo && !draft.canRedo, message: "load is clean and clears history")
    let invalid: [[KitZone]] = [
        [sampleZone(20, 22), sampleZone(10, 12)],
        [sampleZone(10, 20), sampleZone(20, 30)],
        [sampleZone(-1, 10)], [sampleZone(120, 128)], [sampleZone(40, 39)],
    ]
    for (index, zones) in invalid.enumerated() {
        r.expect(!draft.setDrumkitZones(zones), message: "drumkit invalid range \(index) rejected")
        r.expect(!draft.setKeysplitZones(zones), message: "keysplit invalid range \(index) rejected")
        r.expectEqual(expected: initial, actual: draft.snapshot(), what: "rejection \(index) preserves both views")
    }
    r.expect(!draft.canUndo && !draft.dirty, message: "rejected edits create no undo or dirtiness")
    r.expect(draft.setDrumkitZones([sampleZone(11, 13)]), message: "legal drumkit edit accepted")
    let drumEdit = draft.snapshot()
    r.expect(draft.dirty && draft.canUndo, message: "accepted edit is dirty and undoable")
    r.expect(draft.setKeysplitZones([sampleZone(1, 100)]), message: "legal keysplit edit accepted")
    let bothEdited = draft.snapshot()
    draft.markClean()
    r.expect(!draft.dirty && draft.canUndo, message: "markClean keeps undo")
    draft.undo()
    r.expectEqual(expected: drumEdit, actual: draft.snapshot(), what: "undo restores both views")
    r.expect(draft.dirty && draft.canRedo, message: "undo away from clean is dirty")
    draft.redo()
    r.expectEqual(expected: bothEdited, actual: draft.snapshot(), what: "redo restores both views")
    r.expect(!draft.dirty, message: "redo to clean snapshot clears dirty")
    draft.undo()
    draft.undo()
    r.expectEqual(expected: initial, actual: draft.snapshot(), what: "second undo restores loaded snapshot")
    r.expect(draft.dirty && !draft.canUndo && draft.canRedo, message: "clean marker follows values not history depth")
    r.expect(draft.setDrumkitZones([]), message: "new branch accepted")
    r.expect(!draft.canRedo, message: "new edit drops redo branch")
    draft.load(initial)
    draft.undo()
    draft.redo()
    r.expectEqual(expected: initial, actual: draft.snapshot(), what: "load clears undo and redo")
    r.expect(!draft.dirty && !draft.canUndo && !draft.canRedo, message: "reloaded snapshot remains clean")
    r.expect(draft.setDrumkitZones([sampleZone(11, 13)]), message: "edit after reload accepted")
    draft.undo()
    r.expect(!draft.dirty, message: "undo to loaded clean snapshot clears dirty")
}

private func checkKitDrumkitCodec(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitDraft::drumkitCodec")
    let noise = VgVoice(macro: .noise, key: 45, period: 1, attack: 2, decay: 3, sustain: 12, release: 0)
    let zones = [
        sampleZone(10, 12, pan: -32), sampleZone(30, 33, pitched: true, pan: 62), lockedZone(50, 51, voice: noise),
    ]
    let children = KitDraftCodec.children(from: zones, mode: .drumkit)
    r.expectEqual(expected: 128, actual: children.count, what: "drumkit always has 128 sub-slots")
    r.expect(children[9] == nil && children[127] == nil, message: "unassigned drumkit keys are nil")
    r.expectEqual(
        expected: [60, 60, 60], actual: children[10...12].map { $0?.key ?? -1 }, what: "unpitched child keys equal root"
    )
    r.expectEqual(
        expected: [60, 61, 62, 63], actual: children[30...33].map { $0?.key ?? -1 },
        what: "pitched child keys rise by one")
    r.expectEqual(expected: 48, actual: children[10]?.pan, what: "negative pan encoded for rhythm byte")
    r.expectEqual(expected: 95, actual: children[30]?.pan, what: "positive pan encoded for rhythm byte")
    r.expectEqual(expected: noise, actual: children[50], what: "locked voice preserved in drumkit")
    r.expectEqual(
        expected: zones, actual: KitDraftCodec.drumkitZones(children: children),
        what: "drumkit round trip retains pitch pan blank and locked runs")
    var materialized = children
    let blank = VgVoice(macro: .square1, sustain: 15)
    for index in materialized.indices where materialized[index] == nil { materialized[index] = blank }
    r.expectEqual(
        expected: zones, actual: KitDraftCodec.drumkitZones(children: materialized),
        what: "serialized blank children reload as unassigned")
    do {
        let parsed = try VoicegroupText.parse(bytes: Array(kitBlankChildLine.utf8))
        r.expect(
            parsed.voices[0]?.type == vgMacroVoiceType(blank.macro)
                && parsed.voices[0]?.key == UInt8(blank.key) && parsed.voices[0]?.sustain == UInt8(blank.sustain),
            message: "blank comparison fixture matches public blank line")
    } catch { r.fail("blank line did not decode: \(error)") }
    var broken = [VgVoice?](repeating: nil, count: 128)
    let same = VgVoice(key: 60, symbol: "same", attack: 255)
    broken[0] = same
    broken[1] = same
    var rising = same
    rising.key = 61
    broken[2] = rising
    rising.key = 62
    broken[3] = rising
    rising.key = 70
    broken[4] = rising
    rising.attack = 254
    broken[5] = rising
    let collapsed = KitDraftCodec.drumkitZones(children: broken)
    r.expectEqual(
        expected: [0, 2, 4, 5], actual: collapsed.map(\.startKey),
        what: "broken key progression and parameter change split runs")
    r.expectEqual(expected: [1, 3, 4, 5], actual: collapsed.map(\.endKey), what: "equal and rising runs maximal")
    r.expect(!collapsed[0].pitched && collapsed[1].pitched, message: "collapse identifies unpitched versus rising runs")
    for macro in [VgMacro.directSound, .directSoundNoResample, .directSoundAlt] {
        var original = [VgVoice?](repeating: nil, count: 128)
        original[60] = VgVoice(macro: macro, pan: 64, symbol: "variant", attack: 255)
        let loaded = KitDraftCodec.drumkitZones(children: original)
        r.expectEqual(expected: macro, actual: loaded.first?.sampleMacro, what: "\(macro) load preserves sample macro")
        r.expectEqual(
            expected: original, actual: KitDraftCodec.children(from: loaded, mode: .drumkit),
            what: "\(macro) child round trip preserves sample macro")
        let splitTable = KitDraftCodec.table(from: loaded, name: "variant")
        let splitChildren = KitDraftCodec.children(from: loaded, mode: .keysplit)
        r.expectEqual(
            expected: macro, actual: splitChildren[0]?.macro, what: "\(macro) keysplit child preserves sample macro")
        r.expectEqual(
            expected: macro,
            actual: KitDraftCodec.keysplitZones(children: splitChildren, table: splitTable).first?.sampleMacro,
            what: "\(macro) keysplit load preserves sample macro")
        var rendered = ProcessedSample()
        rendered.s8 = [1]
        rendered.freq = 13_700_096
        let tone = KitDraftCodec.auditionTone(
            draft: KitDraft.Snapshot(drumkitZones: loaded), mode: .drumkit, key: 60,
            samples: ["variant": rendered], progWaves: [:])
        if let tone, case .sample(_, _, _, _, _, let kind, _, _) = tone.children[60] {
            r.expectEqual(
                expected: Int(vgMacroVoiceType(macro)), actual: kind, what: "\(macro) audition engine type retained")
        } else {
            r.fail("\(macro) audition sample missing")
        }
    }
}

private func checkKitKeysplitCodec(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitDraft::keysplitCodec")
    let square = VgVoice(macro: .square2, duty: 1, attack: 1, decay: 2, sustain: 12, release: 0)
    let zones = [sampleZone(10, 20), lockedZone(40, 50, voice: square), sampleZone(70, 100, name: "other")]
    let children = KitDraftCodec.children(from: zones, mode: .keysplit)
    let table = KitDraftCodec.table(from: zones, name: "keysplit_test")
    r.expectEqual(expected: 4, actual: children.count, what: "one nil sentinel appended when gaps exist")
    r.expect(children[3] == nil && children[1] == square, message: "locked ordinal retained and gap sentinel nil")
    r.expectEqual(expected: 0, actual: children[0]?.pan, what: "keysplit does not write rhythm pan")
    r.expectEqual(expected: 0, actual: table.startingNote, what: "table starts at zero")
    r.expectEqual(expected: 128, actual: table.maxNote, what: "table covers full range")
    r.expectEqual(expected: 128, actual: table.table.count, what: "table is 128 bytes")
    r.expect(
        table.table[0] == 3 && table.table[30] == 3 && table.table[127] == 3,
        message: "leading middle and top gaps map to the sentinel")
    r.expect(
        table.table[10] == 0 && table.table[45] == 1 && table.table[100] == 2,
        message: "assigned keys map to sorted zone ordinals")
    r.expectEqual(
        expected: zones, actual: KitDraftCodec.keysplitZones(children: children, table: table),
        what: "keysplit round trip preserves all gaps and locked voice")
    var materialized = children
    materialized[3] = VgVoice(macro: .square1, sustain: 15)
    r.expectEqual(
        expected: zones, actual: KitDraftCodec.keysplitZones(children: materialized, table: table),
        what: "materialized sentinel stays unassigned")
    let complete = [sampleZone(0, 63), sampleZone(64, 127, name: "other")]
    let fullChildren = KitDraftCodec.children(from: complete, mode: .keysplit)
    r.expectEqual(expected: 2, actual: fullChildren.count, what: "no gaps means no sentinel child")
    let fullTable = KitDraftCodec.table(from: complete, name: "full")
    r.expectEqual(
        expected: complete, actual: KitDraftCodec.keysplitZones(children: fullChildren, table: fullTable),
        what: "full range round trip")
    r.expectEqual(
        expected: 1, actual: KitDraftCodec.children(from: [], mode: .keysplit).count,
        what: "empty kit has one silent sentinel")
    r.expectEqual(
        expected: [],
        actual: KitDraftCodec.keysplitZones(children: [nil], table: KitDraftCodec.table(from: [], name: "empty")),
        what: "empty kit round trip")
    var invalid = table.table
    invalid[10] = 127
    let invalidTable = KeysplitTable(name: "invalid", startingNote: 0, maxNote: 128, table: invalid)
    let loaded = KitDraftCodec.keysplitZones(children: children, table: invalidTable)
    r.expectEqual(expected: 11, actual: loaded.first?.startKey, what: "undefined child index leaves unassigned key")
    let reordered = [zones[2], zones[0], zones[1]]
    r.expectEqual(
        expected: children, actual: KitDraftCodec.children(from: reordered, mode: .keysplit),
        what: "keysplit ordinals sort by start key")
    r.expectEqual(
        expected: table, actual: KitDraftCodec.table(from: reordered, name: table.name),
        what: "table uses same sorted ordinals")
}

private func checkKitToneCodec(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitDraft::auditionTone")
    let noise = VgVoice(macro: .noiseAlt, key: 44, pan: 0, period: 1, attack: 2, decay: 3, sustain: 10, release: 4)
    let wave = VgVoice(macro: .progWave, key: 60, symbol: "wave", attack: 1, decay: 2, sustain: 15, release: 3)
    let snapshot = KitDraft.Snapshot(
        drumkitZones: [
            sampleZone(10, 12, pan: -32), sampleZone(30, 32, pitched: true, pan: 62), lockedZone(50, 50, voice: noise),
        ],
        keysplitZones: [sampleZone(0, 20), lockedZone(30, 40, voice: wave)])
    var sample = ProcessedSample()
    sample.s8 = [1, 2, -3]
    sample.freq = 13_700_096
    sample.looped = true
    sample.loopStart = 1
    let samples = ["slice": sample]
    let words: [UInt32] = [1, 2, 3, 4]
    guard
        let drum = KitDraftCodec.auditionTone(
            draft: snapshot, mode: .drumkit, key: 31, samples: samples, progWaves: [:])
    else {
        r.fail("assigned drumkit key has no tone")
        return
    }
    r.expect(
        drum.mode == .drumkit && drum.splitTable == nil && drum.children.count == 128, message: "drumkit wrapper shape")
    if case .sample(let pcm, let frequency, let key, let pan, let adsr, let kind, let looped, let loopStart) =
        drum.children[31]
    {
        r.expectEqual(expected: sample.s8, actual: pcm, what: "rendered slice PCM referenced")
        r.expectEqual(expected: sample.freq, actual: frequency, what: "rendered frequency retained")
        r.expectEqual(expected: UInt8(61), actual: key, what: "pitched drumkit child key")
        r.expectEqual(expected: UInt8(0xDF), actual: pan, what: "positive rhythm pan byte")
        r.expect(
            adsr.attack == 255 && adsr.decay == 4 && adsr.sustain == 200 && adsr.release == 0,
            message: "sample ADSR retained")
        r.expect(
            kind == Int(vgMacroVoiceType(.directSound)) && looped && loopStart == 1,
            message: "sample engine type and rendered loop metadata retained")
    } else {
        r.fail("sample zone did not build sample child")
    }
    if case .sample(_, _, let key, let pan, _, _, _, _) = drum.children[12] {
        r.expectEqual(expected: UInt8(60), actual: key, what: "unpitched drumkit child keeps root")
        r.expectEqual(expected: UInt8(0xB0), actual: pan, what: "negative rhythm pan byte")
    } else {
        r.fail("unpitched child missing")
    }
    if case .psg(let psg) = drum.children[50] {
        r.expect(
            psg.kind == Int(noise.macro.rawValue) && psg.key == noise.key && psg.pan == noise.pan
                && psg.period == noise.period && psg.sweep == noise.sweep && psg.duty == noise.duty,
            message: "locked descriptor copies raw kind and pitch fields")
        r.expect(
            psg.attack == noise.attack && psg.decay == noise.decay && psg.sustain == noise.sustain
                && psg.release == noise.release,
            message: "locked descriptor copies envelope")
    } else {
        r.fail("locked child missing")
    }
    r.expect(
        KitDraftCodec.auditionTone(draft: snapshot, mode: .drumkit, key: 29, samples: samples, progWaves: [:]) == nil,
        message: "unassigned clicked key has no tone")
    guard
        let split = KitDraftCodec.auditionTone(
            draft: snapshot, mode: .keysplit, key: 35, samples: samples, progWaves: ["wave": words])
    else {
        r.fail("assigned keysplit key has no tone")
        return
    }
    r.expect(
        split.mode == .keysplit && split.children.count == 3 && split.splitTable?[35] == 1
            && split.splitTable?[127] == 2,
        message: "explicit active view builds keysplit wrapper and gap sentinel")
    if case .sample(_, _, let key, let pan, _, _, _, _) = split.children[0] {
        r.expect(key == 60 && pan == 0, message: "keysplit child root retained without rhythm pan")
    } else {
        r.fail("keysplit sample child missing")
    }
    if case .psg(let psg) = split.children[1] {
        r.expectEqual(expected: words, actual: psg.progWave, what: "caller supplied programmable wave words retained")
    } else {
        r.fail("programmable descriptor missing")
    }
    guard
        let missing = KitDraftCodec.auditionTone(draft: snapshot, mode: .drumkit, key: 10, samples: [:], progWaves: [:])
    else {
        r.fail("missing asset must preserve assigned wrapper")
        return
    }
    if case .sample(let pcm, _, _, _, _, _, _, _) = missing.children[10] {
        r.expect(pcm.isEmpty, message: "missing sample symbol becomes silent child")
    } else {
        r.fail("missing sample not silent")
    }
    guard
        let missingWave = KitDraftCodec.auditionTone(
            draft: snapshot, mode: .keysplit, key: 35, samples: samples, progWaves: [:])
    else {
        r.fail("missing programmable asset must preserve assigned wrapper")
        return
    }
    if case .psg(let psg) = missingWave.children[1] {
        r.expect(psg.progWave == nil, message: "missing programmable symbol stays absent")
    } else {
        r.fail("missing programmable descriptor not preserved")
    }
}
