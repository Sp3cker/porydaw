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
    runKitSourceSessionChecks(report)
    checkKitPresenterPicker(report)
    checkKitPresenterZones(report)
    checkKitPresenterPrompts(report)
    checkKitPresenterDirty(report)
    checkKitPresenterSlices(report)
    checkKitPresenterLoadAndAudition(report)
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

@MainActor
private func presenterVoices() -> [VgVoice?] {
    var voices = [VgVoice?](repeating: nil, count: 128)
    voices[0] = VgVoice(macro: .directSound, symbol: "ordinary")
    voices[2] = VgVoice(macro: .keysplitAll, symbol: "voicegroup_kit")
    voices[4] = VgVoice(macro: .keysplit, symbol: "voicegroup_keys", keysplitTable: "keys")
    return voices
}

@MainActor
private func checkKitPresenterPicker(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::pickerAndUsage")
    let p = KitStudioPresenter()
    let voices = presenterVoices()
    var loaded: [Int] = []
    var scanned: [String] = []
    p.onLoadKit = { (slot: Int) -> KitLoadResult? in
        loaded.append(slot)
        return KitLoadResult(
            kind: .drumkit, parent: voices[slot],
            children: KitDraftCodec.children(from: [sampleZone(10, 12)], mode: .drumkit))
    }
    p.usageScan = { (subgroup: String, table: String?, section: String) -> [String] in
        scanned = [subgroup, table ?? "", section]
        return ["voicegroup_fixture_rich", "voicegroup_other", "voicegroup_other", "voicegroup_third"]
    }
    p.bind(song: "Song", section: "voicegroup_fixture_rich", voices: voices, slot: 2)
    r.expectEqual(expected: 127, actual: p.slotRows.count, what: "picker excludes scalar voices")
    let emptyCount = (0..<p.slotRows.count).filter { (index: Int) -> Bool in p.slotRows[index].isNew }.count
    r.expectEqual(expected: 125, actual: emptyCount, what: "every undefined slot offered")
    r.expectEqual(expected: "New kit in empty slot 1…", actual: p.slotRows[0].title, what: "new kit label")
    r.expectEqual(expected: [2], actual: loaded, what: "clean target loads silently")
    r.expectEqual(
        expected: ["voicegroup_kit", "", "voicegroup_fixture_rich"], actual: scanned,
        what: "canonical section feeds scanner")
    r.expectEqual(expected: "used by 2", actual: p.usedByText, what: "usage excludes bound section and duplicates")
    r.expectEqual(expected: "Split Studio — Song · voice 2", actual: p.titleText, what: "clean title")
    let existing = p.slotRows[1]
    p.refresh()
    r.expect(p.slotRows[1] === existing, message: "unchanged rows retain identity")
    p.selectSlot(row: 0)
    r.expectEqual(expected: 1, actual: p.selectedSlot, what: "new empty target selected")
    r.expect(p.draft.drumkitZones.isEmpty && !p.dirty && !p.canSave, message: "new kit starts clean and empty")
    r.expectEqual(expected: [2], actual: loaded, what: "new kit does not request project creation or load")
}

@MainActor
private func checkKitPresenterZones(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::zonesAndViews")
    let p = KitStudioPresenter()
    p.bind(song: "Song", section: "voicegroup_song", voices: presenterVoices(), slot: 1)
    p.dropSample(name: "a", onKey: 10)
    p.dropSample(name: "b", onKey: 20)
    r.expectEqual(
        expected: [10, 20], actual: p.draft.drumkitZones.map(\.endKey), what: "drumkit drops are one-key zones")
    let twoZones = p.draft.snapshot()
    p.dropSample(name: "occupied", onKey: 10)
    r.expectEqual(expected: twoZones, actual: p.draft.snapshot(), what: "occupied drop never merges")
    r.expect(!p.statusText.isEmpty, message: "occupied drop reports rejection")
    p.resizeZone(row: 0, startKey: 10, endKey: 19)
    let resized = p.draft.snapshot()
    p.resizeZone(row: 0, startKey: 10, endKey: 20)
    r.expectEqual(expected: resized, actual: p.draft.snapshot(), what: "resize overlap rejected by draft")
    p.moveZone(row: 0, toKey: 20)
    r.expectEqual(expected: resized, actual: p.draft.snapshot(), what: "move overlap rejected by draft")
    r.expectEqual(expected: 19, actual: p.zoneRows[0].endKey, what: "rejected resize republishes authoritative rows")
    p.moveZone(row: 0, toKey: 126)
    r.expectEqual(
        expected: [20, 118], actual: p.draft.drumkitZones.map(\.startKey),
        what: "move sorts and visibly clamps to keyboard")
    p.undo()
    r.expectEqual(expected: resized, actual: p.draft.snapshot(), what: "one undo restores accepted resize state")
    p.selectZone(row: 0)
    p.setZonePan(pan: -32)
    let drumkit = p.draft.drumkitZones
    p.setMode(index: 1)
    p.dropSample(name: "right", onKey: 30)
    p.dropSample(name: "left", onKey: 10)
    r.expectEqual(
        expected: [29, 127], actual: p.draft.keysplitZones.map(\.endKey), what: "keysplit extends to next zone or 127")
    let split = p.draft.keysplitZones
    p.dropSample(name: "occupied", onKey: 20)
    r.expectEqual(expected: split, actual: p.draft.keysplitZones, what: "keysplit occupied range rejects drop")
    p.selectZone(row: 0)
    p.setZonePan(pan: 63)
    p.setZonePitched(on: false)
    r.expectEqual(expected: split, actual: p.draft.keysplitZones, what: "unstoreable pan and pitch flag stay disabled")
    r.expect(
        p.zoneRows[0].pitched && !p.zoneRows[0].pitchedEnabled && !p.zoneRows[0].panEnabled,
        message: "keysplit shows inherently pitched and disables rhythm controls")
    p.setZoneRootKey(key: 48)
    r.expectEqual(expected: 48, actual: p.draft.keysplitZones[0].rootKey, what: "keysplit root remains editable")
    p.setMode(index: 0)
    r.expectEqual(expected: drumkit, actual: p.draft.drumkitZones, what: "drumkit edits survive mode switches")
    r.expectEqual(expected: -32, actual: p.zoneRows[0].pan, what: "drumkit pan restored")
    p.setMode(index: 1)
    r.expectEqual(expected: 48, actual: p.zoneRows[0].rootKey, what: "keysplit edits survive mode switches")
}

@MainActor
private func checkKitPresenterPrompts(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::conflictAndRetarget")
    let p = KitStudioPresenter()
    let voices = presenterVoices()
    var loads: [Int] = []
    var answers: [Int] = []
    var conflicts: [Bool] = []
    p.onLoadKit = { (slot: Int) -> KitLoadResult? in
        loads.append(slot)
        return KitLoadResult(
            kind: .drumkit, parent: voices[slot],
            children: KitDraftCodec.children(from: [sampleZone(10, 10)], mode: .drumkit))
    }
    p.onRetargetPrompt = { answers.append($0) }
    p.onConflictAnswer = { conflicts.append($0) }
    p.bind(song: "Song", section: "voicegroup_song", voices: voices, slot: 2)
    p.songKitChanged()
    r.expectEqual(expected: [2, 2], actual: loads, what: "clean song-side change reloads")
    p.dropSample(name: "mine", onKey: 20)
    let mine = p.draft.snapshot()
    p.songKitChanged()
    r.expect(
        p.conflictVisible && p.conflictText == "Changed in the song",
        message: "dirty song change shows exact conflict bar")
    p.answerConflict(keepMine: true)
    r.expect(
        !p.conflictVisible && p.dirty && p.draft.snapshot() == mine, message: "Keep mine hides bar and preserves draft")
    p.songKitChanged()
    p.answerConflict(keepMine: false)
    r.expect(
        !p.conflictVisible && !p.dirty && p.zoneRows.count == 1, message: "Reload replaces draft and clears conflict")
    r.expectEqual(expected: [true, false], actual: conflicts, what: "workflow receives both conflict answers")
    p.dropSample(name: "dirty", onKey: 20)
    let targetRow = (0..<p.slotRows.count).first { (index: Int) -> Bool in p.slotRows[index].slot == 4 } ?? -1
    p.selectSlot(row: targetRow)
    r.expect(
        p.retargetVisible && p.retargetSlot == 4 && p.selectedSlot == 2,
        message: "dirty picker change emits revision-backed prompt")
    p.answerRetarget(answer: 2)
    r.expect(!p.retargetVisible && p.selectedSlot == 2 && p.dirty, message: "Cancel keeps current target")
    p.selectSlot(row: targetRow)
    p.answerRetarget(answer: 0)
    r.expect(p.retargetVisible && p.selectedSlot == 2, message: "Save waits for workflow completion")
    p.markClean()
    p.completeRetarget()
    r.expect(!p.retargetVisible && p.selectedSlot == 4 && !p.dirty, message: "successful save continuation retargets")
    p.dropSample(name: "dirtyAgain", onKey: 20)
    p.selectSlot(row: 1)
    p.answerRetarget(answer: 1)
    r.expect(p.selectedSlot == 2 && !p.dirty && !p.retargetVisible, message: "Discard loads the pending target")
    r.expectEqual(
        expected: [2, 0, 1], actual: answers, what: "prompt answers use exact 0 save 1 discard 2 cancel values")
}

@MainActor
private func checkKitPresenterDirty(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::dirtyTitleAndSave")
    let p = KitStudioPresenter()
    p.bind(song: "Song", section: "voicegroup_song", voices: presenterVoices(), slot: 1)
    p.setMode(index: 1)
    r.expect(p.dirty && p.canSave && !p.canUndo, message: "mode-only conversion is saveable but not a history entry")
    p.setMode(index: 0)
    r.expect(!p.dirty && !p.canSave, message: "original clean mode clears dirty")
    var saves = 0
    p.onSaveRequested = { saves += 1 }
    p.requestSave()
    p.dropSample(name: "sample", onKey: 60)
    p.requestSave()
    r.expectEqual(expected: 1, actual: saves, what: "Save callback gated by selected dirty target")
    r.expectEqual(expected: "Split Studio — Song · voice 1 •", actual: p.titleText, what: "dirty title suffix")
    p.markClean()
    r.expect(!p.dirty && !p.canSave && p.canUndo, message: "save marks clean and keeps history")
    r.expect(!p.slotRows[0].isNew, message: "saved empty slot becomes existing kit offer")
    p.undo()
    r.expect(p.dirty && p.canSave && p.canRedo, message: "undo away from save is dirty")
    p.redo()
    r.expect(!p.dirty && !p.canSave && !p.canRedo, message: "redo to saved values restores clean")
    p.bind(song: "Song", section: "voicegroup_song", voices: presenterVoices(), slot: 0)
    p.dropSample(name: "notAkit", onKey: 60)
    r.expect(
        p.selectedSlot == -1 && !p.canSave && p.draft.drumkitZones.isEmpty,
        message: "non-kit target cannot be edited or saved")
}

@MainActor
private func checkKitPresenterSlices(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::sliceMappingValidationAndHistory")
    let p = KitStudioPresenter()
    p.bind(song: "Song", section: "voicegroup_song", voices: presenterVoices(), slot: 1)
    r.expect(p.snap, message: "zero-crossing snap starts enabled")
    p.toggleSnap()
    p.addSource(ImportedSample(buffer: [Float](repeating: 0.5, count: 128), sampleRate: 13379, suggestedName: "source"))
    p.selectionStartFrame = 10
    p.selectionEndFrame = 100
    p.sliceSelection()
    p.cursorFrame = 50
    p.addMarkerAtCursor()
    let id = p.sliceId(row: 0)
    let secondId = p.sliceId(row: 1)
    let middleMarker = p.markerId(row: 1)
    p.moveMarker(id: middleMarker, toFrame: 60)
    r.expect(
        p.markerId(row: 1) == middleMarker && p.sliceStartFrame(id: secondId) == 60,
        message: "moving marker keeps presenter ids and updates index mapping")
    p.undo()
    r.expect(
        p.markerId(row: 1) == middleMarker && p.sliceStartFrame(id: secondId) == 50,
        message: "marker undo restores mapped frames and ids")
    p.redo()
    p.undo()
    let oldName = p.sliceName(id: id)
    r.expect(id > 0 && secondId > 0 && id != secondId, message: "presenter owns unique QML slice ids")
    r.expect(
        p.sliceAddress(id)?.index == 0 && p.sliceAddress(secondId)?.index == 1, message: "ids map to session indices")
    var validated: [String] = []
    p.validateName = { (name: String) -> String? in
        validated.append(name)
        return name == "taken" ? "Already registered" : nil
    }
    p.renameSlice(id: id, name: "taken")
    r.expectEqual(expected: oldName, actual: p.sliceName(id: id), what: "adapter refusal preserves name")
    r.expectEqual(expected: "Already registered", actual: p.statusText, what: "adapter refusal is visible")
    p.dropSample(name: oldName, onKey: 10)
    p.setMode(index: 1)
    p.dropSample(name: oldName, onKey: 10)
    p.markClean()
    p.renameSlice(id: id, name: "renamed slice")
    let renamed = SampleNames.sanitize("renamed slice")
    r.expect(validated.contains(renamed), message: "rename uses sanitized validation adapter")
    r.expectEqual(expected: renamed, actual: p.sliceName(id: id), what: "validated rename applied")
    r.expect(
        p.draft.drumkitZones[0].sampleName == renamed && p.draft.keysplitZones[0].sampleName == renamed,
        message: "rename updates mapped zones in both views")
    p.undo()
    r.expect(
        p.sliceName(id: id) == oldName && p.draft.drumkitZones[0].sampleName == oldName
            && p.draft.keysplitZones[0].sampleName == oldName && !p.dirty,
        message: "one undo restores slice plus both views and clean state")
    p.redo()
    r.expect(
        p.sliceName(id: id) == renamed && p.draft.drumkitZones[0].sampleName == renamed
            && p.draft.keysplitZones[0].sampleName == renamed, message: "one redo reapplies compound rename")
    p.undo()
    p.setMode(index: 0)
    p.dropSample(name: p.sliceName(id: secondId), onKey: 20)
    let beforeMerge = p.session.snapshot()
    let beforeDraft = p.draft.snapshot()
    p.removeMarker(id: p.markerId(row: 1))
    r.expectEqual(
        expected: beforeMerge, actual: p.session.snapshot(), what: "in-use merged slice refuses before live mutation")
    r.expectEqual(expected: beforeDraft, actual: p.draft.snapshot(), what: "merge refusal preserves both views")
    r.expectEqual(
        expected: "\(p.sliceName(id: secondId)) is used by a zone; remove those zones first.",
        actual: p.statusText, what: "merge refusal names the slice")
    p.undo()
    r.expectEqual(expected: 1, actual: p.draft.drumkitZones.count, what: "refused merge added no history entry")
    var played = 0
    p.playPcm = { played = $0 }
    p.playSlice(id: id)
    r.expectEqual(expected: id, actual: played, what: "slice audition routes through injected player closure")
    p.setSourceRate(rate: 26758)
    r.expectEqual(expected: 26758, actual: p.sourceRate, what: "source rate chooses Hz value")
    r.expectEqual(
        expected: 20, actual: p.sourceFrame(sliceId: id, renderedPosition: 20),
        what: "rendered playhead maps ratio and slice start")
    r.expectEqual(
        expected: SampleRatePolicy.rateOptions(sourceRate: 13379).map(String.init),
        actual: p.rateChoices, what: "options come only from shared rate policy")
    p.setSourceRate(rate: 12345)
    r.expectEqual(expected: 26758, actual: p.sourceRate, what: "unsupported rate rejected")
    p.setMode(index: 0)
    p.deleteZone(row: 0)
    p.setMode(index: 1)
    p.deleteZone(row: 0)
    p.setMode(index: 0)
    p.mapAllSlices(fromKey: 60, whiteKeysOnly: true)
    r.expectEqual(expected: [60, 62], actual: p.draft.drumkitZones.map(\.startKey), what: "map-all skips black keys")
    let mapped = p.draft.snapshot()
    p.mapAllSlices(fromKey: 60, whiteKeysOnly: true)
    r.expectEqual(expected: mapped, actual: p.draft.snapshot(), what: "map-all occupied keys rejects atomically")
    p.closeSource(row: 0)
    r.expectEqual(expected: 1, actual: p.session.sources.count, what: "source with slices in either view cannot close")
}

@MainActor
private func checkKitPresenterLoadAndAudition(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::loadRangesAndLockedAudition")
    let p = KitStudioPresenter()
    p.bind(song: "Song", section: "voicegroup_song", voices: presenterVoices(), slot: 1)
    let splitZones = [sampleZone(40, 70)]
    let children = KitDraftCodec.children(from: splitZones, mode: .keysplit)
    let table = KitDraftCodec.table(from: splitZones, name: "keys")
    p.install(KitLoadResult(kind: .keysplit, parent: presenterVoices()[4], children: children, table: table), slot: 4)
    r.expect(
        p.mode == 1 && p.draft.drumkitZones == p.draft.keysplitZones,
        message: "actual loaded mode initializes both views with keyboard ranges, not child ordinals")
    r.expectEqual(expected: 40, actual: p.zoneRows[0].startKey, what: "table range start")
    p.setMode(index: 0)
    r.expectEqual(expected: 40, actual: p.zoneRows[0].startKey, what: "first mode switch carries ranges across")
    r.expect(p.dirty && !p.canUndo, message: "mode toggle has no history")
    let noise = VgVoice(macro: .noise, key: 45, period: 1, attack: 2, decay: 3, sustain: 12, release: 0)
    let zones = [sampleZone(10, 10), lockedZone(45, 45, voice: noise)]
    p.install(
        KitLoadResult(
            kind: .drumkit,
            children: KitDraftCodec.children(from: zones, mode: .drumkit)), slot: 2)
    p.selectZone(row: 1)
    let locked = p.draft.snapshot()
    p.setZoneRootKey(key: 90)
    p.setZonePan(pan: 40)
    p.setZonePitched(on: true)
    p.setZoneAdsr(a: 1, d: 2, s: 3, r: 4)
    r.expectEqual(expected: locked, actual: p.draft.snapshot(), what: "locked strip edits preserve original voice")
    r.expect(
        p.selectedZoneRow()?.locked == true && p.selectedZoneRow()?.voiceType == "noise",
        message: "locked selected strip exposes voice type")
    var sample = ProcessedSample()
    sample.s8 = [1, 2, 3]
    sample.freq = 13_700_096
    p.samples = ["slice": sample]
    var samplePlayed = false
    var lockedPlayed = false
    var publishes = 0
    p.publishKitTone = { (tone: KitAuditionTone, key: UInt8) -> Bool in
        publishes += 1
        if key == 10, case .sample(let pcm, _, _, _, _, _, _, _) = tone.children[10] {
            samplePlayed = pcm == sample.s8
        }
        if key == 45, case .psg(let voice) = tone.children[45] {
            lockedPlayed =
                voice.kind == Int(noise.macro.rawValue) && voice.key == noise.key && voice.period == noise.period
        }
        return true
    }
    p.playKey(key: 10)
    p.playKey(key: 45)
    p.playKey(key: 99)
    r.expect(
        samplePlayed && lockedPlayed && publishes == 2,
        message: "key audition publishes draft samples and preserved locked tone only")
    p.moveZone(row: 1, toKey: 46)
    r.expectEqual(
        expected: noise, actual: p.draft.drumkitZones[1].lockedVoice,
        what: "locked zone can move without rewriting voice")
    p.deleteZone(row: 1)
    r.expectEqual(expected: 1, actual: p.draft.drumkitZones.count, what: "locked zone can be deleted")
}
