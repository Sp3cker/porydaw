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
    checkKitPresenterZones(report)
    checkKitPresenterDirty(report)
    checkKitPresenterSlices(report)
    checkKitWholeFileAdd(report)
    checkKitPresenterVoicegroupName(report)
    checkKitPresenterAudition(report)
}

@MainActor
private func checkKitWholeFileAdd(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::wholeFileAdd")
    let p = KitStudioPresenter()
    p.open()
    p.addSource(
        ImportedSample(buffer: [Float](repeating: 0.5, count: 256), sampleRate: 44100, suggestedName: "kick"),
        autoPlaceFirstSlice: true)
    r.expectEqual(expected: 1, actual: p.sliceCount, what: "whole-file add lists one kit slice")
    let firstId = p.sliceId(row: 0)
    r.expect(firstId != 0, message: "kit row zero resolves a slice id")
    r.expectEqual(expected: 1, actual: p.sliceOrdinal(id: firstId), what: "first slice is kit number one")
    let firstName = p.sliceName(id: firstId)
    r.expect(
        p.draft.drumkitZones.contains { (zone: KitZone) -> Bool in zone.sampleName == firstName && zone.startKey == 36
        },
        message: "first one-shot auto-places on C2")
    p.addSource(
        ImportedSample(buffer: [Float](repeating: 0.25, count: 256), sampleRate: 44100, suggestedName: "snare"),
        autoPlaceFirstSlice: true)
    r.expectEqual(expected: 2, actual: p.sliceCount, what: "second file appends to the kit-wide table")
    let secondId = p.sliceId(row: 1)
    r.expect(secondId != 0 && secondId != firstId, message: "kit row one is the new slice")
    r.expectEqual(expected: 2, actual: p.sliceOrdinal(id: secondId), what: "new slice takes kit number two")
    let secondName = p.sliceName(id: secondId)
    r.expect(
        p.draft.drumkitZones.contains { (zone: KitZone) -> Bool in zone.sampleName == secondName && zone.startKey == 37
        },
        message: "second one-shot takes the next free key")
    p.selectSlice(id: secondId)
    r.expectEqual(expected: secondId, actual: p.selectedSlice, what: "row click selects the new slice")
    r.expect(
        p.sliceAddress(secondId)?.source == p.session.sources.last?.id,
        message: "selecting the new row resolves its file tab")
}

private func sampleZone(
    _ start: Int, _ end: Int, name: String = "slice", pan: Int = 0,
    macro: VgMacro = .directSound
) -> KitZone {
    KitZone(
        startKey: start, endKey: end, sampleName: name, rootKey: 60,
        pan: pan, adsr: (255, 4, 200, 0), sampleMacro: macro)
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
    let zones = [sampleZone(10, 12, pan: -32), sampleZone(30, 33, pan: 62)]
    let children = KitDraftCodec.children(from: zones, mode: .drumkit)
    r.expectEqual(expected: 128, actual: children.count, what: "drumkit always has 128 sub-slots")
    r.expect(children[9] == nil && children[127] == nil, message: "unassigned drumkit keys are nil")
    r.expectEqual(
        expected: [60, 60, 60], actual: children[10...12].map { $0?.key ?? -1 }, what: "drumkit child keys equal root"
    )
    r.expectEqual(
        expected: [60, 60, 60, 60], actual: children[30...33].map { $0?.key ?? -1 },
        what: "multi-key drumkit zone encodes every key at the root key")
    r.expectEqual(expected: 48, actual: children[10]?.pan, what: "negative pan encoded for rhythm byte")
    r.expectEqual(expected: 95, actual: children[30]?.pan, what: "positive pan encoded for rhythm byte")
    for macro in [VgMacro.directSound, .directSoundNoResample, .directSoundAlt] {
        let loaded = [sampleZone(60, 60, name: "variant", macro: macro)]
        r.expectEqual(
            expected: macro, actual: KitDraftCodec.children(from: loaded, mode: .drumkit)[60]?.macro,
            what: "\(macro) drumkit child preserves sample macro")
        let splitChildren = KitDraftCodec.children(from: loaded, mode: .keysplit)
        r.expectEqual(
            expected: macro, actual: splitChildren[0]?.macro, what: "\(macro) keysplit child preserves sample macro")
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
    let zones = [sampleZone(10, 20), sampleZone(40, 50, name: "middle"), sampleZone(70, 100, name: "other")]
    let children = KitDraftCodec.children(from: zones, mode: .keysplit)
    let table = KitDraftCodec.table(from: zones, name: "keysplit_test")
    r.expectEqual(expected: 4, actual: children.count, what: "one nil sentinel appended when gaps exist")
    r.expect(children[3] == nil && children[1]?.symbol == "middle", message: "ordinal retained and gap sentinel nil")
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
    let complete = [sampleZone(0, 63), sampleZone(64, 127, name: "other")]
    let fullChildren = KitDraftCodec.children(from: complete, mode: .keysplit)
    r.expectEqual(expected: 2, actual: fullChildren.count, what: "no gaps means no sentinel child")
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
    let snapshot = KitDraft.Snapshot(
        drumkitZones: [sampleZone(10, 12, pan: -32), sampleZone(30, 32, pan: 62)],
        keysplitZones: [sampleZone(0, 20), sampleZone(30, 40, name: "wave", macro: .progWave)])
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
        r.expectEqual(expected: UInt8(60), actual: key, what: "drumkit child keeps root")
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
        r.expectEqual(expected: UInt8(60), actual: key, what: "drumkit child keeps root")
        r.expectEqual(expected: UInt8(0xB0), actual: pan, what: "negative rhythm pan byte")
    } else {
        r.fail("drumkit child missing")
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
private func checkKitPresenterZones(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::zonesAndViews")
    let p = KitStudioPresenter()
    p.open()
    p.dropSample(name: "a", onKey: 10)
    p.dropSample(name: "b", onKey: 20)
    r.expectEqual(
        expected: [10, 20], actual: p.draft.drumkitZones.map(\.endKey), what: "drumkit drops are one-key zones")
    let twoZones = p.draft.snapshot()
    p.dropSample(name: "occupied", onKey: 10)
    r.expectEqual(expected: twoZones, actual: p.draft.snapshot(), what: "occupied drop never merges")
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
    p.setZonePan(pan: -100)
    r.expectEqual(expected: -64, actual: p.draft.drumkitZones[0].pan, what: "pan clamps to -64")
    p.setZonePan(pan: 100)
    r.expectEqual(expected: 63, actual: p.draft.drumkitZones[0].pan, what: "pan clamps to 63")
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
    r.expectEqual(expected: split, actual: p.draft.keysplitZones, what: "keysplit pan stays disabled")
    r.expect(!p.zoneRows[0].panEnabled, message: "keysplit disables the rhythm pan control")
    p.setZoneRootKey(key: 48)
    r.expectEqual(expected: 48, actual: p.draft.keysplitZones[0].rootKey, what: "keysplit root remains editable")
    p.setMode(index: 0)
    r.expectEqual(expected: drumkit, actual: p.draft.drumkitZones, what: "drumkit edits survive mode switches")
    r.expectEqual(expected: -32, actual: p.zoneRows[0].pan, what: "drumkit pan restored")
    p.setMode(index: 1)
    r.expectEqual(expected: 48, actual: p.zoneRows[0].rootKey, what: "keysplit edits survive mode switches")
}


@MainActor
private func checkKitPresenterDirty(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::dirtyTitleAndSave")
    let p = KitStudioPresenter()
    p.open()
    r.expectEqual(expected: "Split Studio", actual: p.titleText, what: "clean title names no song or voice")
    r.expect(!p.dirty && !p.canSave, message: "empty kit starts clean and unsaveable")
    p.setMode(index: 1)
    r.expect(p.dirty && !p.canSave && !p.canUndo, message: "mode-only conversion is dirty but has no mapped zone")
    p.setMode(index: 0)
    r.expect(!p.dirty && !p.canSave, message: "original clean mode clears dirty")
    p.validateVoicegroupName = { (name: String) -> String? in name == "kit" ? nil : "taken" }
    p.applySuggestedVoicegroupName("kit")
    var saves = 0
    p.onSaveRequested = { saves += 1 }
    p.requestSave()
    r.expectEqual(expected: 0, actual: saves, what: "Save callback gated by mapped zones")
    p.dropSample(name: "sample", onKey: 60)
    p.requestSave()
    r.expectEqual(expected: 1, actual: saves, what: "Save callback fires for a mapped, validly named kit")
    r.expectEqual(expected: "Split Studio •", actual: p.titleText, what: "dirty title suffix")
    p.markClean()
    r.expect(!p.dirty && p.canSave && p.canUndo, message: "save marks clean and keeps history")
    p.undo()
    r.expect(p.dirty && !p.canSave && p.canRedo, message: "undoing the only mapped zone blocks saving")
    p.redo()
    r.expect(!p.dirty && p.canSave && !p.canRedo, message: "redo to saved values restores clean")
    p.setVoicegroupName(name: "taken")
    r.expect(p.voicegroupNameInvalid && !p.canSave, message: "taken name blocks saving")
    p.requestSave()
    r.expectEqual(expected: 1, actual: saves, what: "invalid name suppresses the Save callback")
}

@MainActor
private func checkKitPresenterSlices(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::sliceMappingValidationAndHistory")
    let p = KitStudioPresenter()
    p.open()
    r.expect(p.snap, message: "zero-crossing snap starts enabled")
    p.toggleSnap()
    p.addSource(ImportedSample(buffer: [Float](repeating: 0.5, count: 128), sampleRate: 13379, suggestedName: "source"))
    p.insertMarker(frame: 10)
    p.insertMarker(frame: 100)
    p.insertMarker(frame: 50)
    let id = p.sliceId(row: 0)
    let secondId = p.sliceId(row: 1)
    let secondName = p.sliceName(id: secondId)
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
    r.expect(
        p.sliceAddress(id)?.index == 0 && p.sliceAddress(secondId)?.index == 1, message: "ids map to session indices")
    p.validateName = { (name: String) -> String? in
        name == "taken" ? "Already registered" : nil
    }
    p.renameSlice(id: id, name: "taken")
    r.expectEqual(expected: oldName, actual: p.sliceName(id: id), what: "adapter refusal preserves name")
    p.dropSample(name: oldName, onKey: 10)
    p.setMode(index: 1)
    p.dropSample(name: oldName, onKey: 10)
    p.markClean()
    p.renameSlice(id: id, name: "renamed slice")
    let renamed = SampleNames.sanitize("renamed slice")
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
    p.removeMarker(id: p.markerId(row: 1))
    r.expectEqual(
        expected: 1, actual: p.session.sources[0].slices.count, what: "marker removal merges the split pair")
    r.expectEqual(
        expected: oldName, actual: p.session.sources[0].slices[0].name, what: "merge keeps the left slice name")
    r.expect(
        p.draft.drumkitZones.allSatisfy { $0.sampleName != secondName }
            && p.draft.keysplitZones.allSatisfy { $0.sampleName != secondName },
        message: "merged-away slice unmaps its zones in both views")
    p.undo()
    r.expectEqual(expected: 2, actual: p.session.sources[0].slices.count, what: "merge undo restores both slices")
    r.expect(
        p.draft.drumkitZones.contains { $0.sampleName == secondName }
            && p.draft.keysplitZones.contains { $0.sampleName == secondName },
        message: "merge undo restores the removed zones")
    let zonesBeforeRate = p.draft.snapshot()
    p.setSourceRate(rate: 26758)
    r.expectEqual(expected: 26758, actual: p.sourceRate, what: "source rate chooses Hz value")
    r.expect(!p.canRedo, message: "source edit after zone undo discards the redo branch")
    p.undo()
    r.expect(
        p.sourceRate == 13379 && p.draft.snapshot() == zonesBeforeRate,
        message: "source edit undo restores the rate and leaves zones intact")
    p.redo()
    r.expectEqual(expected: 26758, actual: p.sourceRate, what: "source edit redo follows the zone edit")
    p.setSourceRate(rate: 12345)
    r.expectEqual(expected: 26758, actual: p.sourceRate, what: "unsupported rate rejected")
    p.setMode(index: 0)
    p.deleteZone(row: 0)
    p.setMode(index: 1)
    p.deleteZone(row: 0)
    p.setMode(index: 0)
    p.closeSource(row: 0)
    r.expect(p.session.sources.isEmpty, message: "source with auto-unmapped slices closes")
    r.expect(
        p.draft.drumkitZones.isEmpty && p.draft.keysplitZones.isEmpty,
        message: "closing a source removes its slices' zones in both views")
}

@MainActor
private func checkKitPresenterAudition(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::keyAudition")
    let p = KitStudioPresenter()
    p.open()
    p.dropSample(name: "slice", onKey: 10)
    var sample = ProcessedSample()
    sample.s8 = [1, 2, 3]
    sample.freq = 13_700_096
    p.samples = ["slice": sample]
    var samplePlayed = false
    var publishes = 0
    p.publishKitTone = { (tone: KitAuditionTone, key: UInt8) -> Bool in
        publishes += 1
        if key == 10, case .sample(let pcm, _, _, _, _, _, _, _) = tone.children[10] {
            samplePlayed = pcm == sample.s8
        }
        return true
    }
    p.playKey(key: 10)
    p.playKey(key: 99)
    r.expect(samplePlayed && publishes == 1, message: "key audition publishes mapped sample tone only")

    let kit = KitStudioPresenter()
    kit.open()
    kit.addSource(ImportedSample(buffer: [Float](repeating: 0.5, count: 128), sampleRate: 13379, suggestedName: "src"))
    kit.insertMarker(frame: 10)
    kit.insertMarker(frame: 100)
    kit.insertMarker(frame: 50)
    var played: [Int] = []
    kit.playPcm = { (id: Int) in played.append(id) }
    let second = kit.sliceId(row: 1)
    kit.selectSlice(id: second)
    kit.playSelectedSlice()
    kit.selectSlice(id: -1)
    kit.playSelectedSlice()
    r.expect(
        played == [second, kit.sliceId(row: 0)], message: "space audition plays the selection, else the first slice")
    kit.selectSlice(id: second)
    kit.setZoneRootKey(key: 72)
    kit.setZoneAdsr(a: 10, d: 20, s: 30, r: 40)
    let drum = kit.sliceVoice(id: second)
    r.expect(
        drum?.note == 72 && drum?.adsr.attack == 10 && drum?.adsr.decay == 20 && drum?.adsr.sustain == 30
            && drum?.adsr.release == 40,
        message: "drumkit slice audition sounds the zone root key with its envelope")
    kit.setMode(index: 1)
    kit.selectSlice(id: second)
    kit.setZoneRootKey(key: 100)
    r.expect(
        kit.sliceVoice(id: second)?.note == UInt8(kit.selectedZoneLastKey),
        message: "keysplit slice audition clamps the root key into the zone")
    kit.deleteZone(row: kit.selectedZone)
    r.expect(kit.sliceVoice(id: second) == nil, message: "unmapped slice audition has no voice")
}

@MainActor
private func checkKitPresenterVoicegroupName(_ report: CheckReport) {
    let r = report.scoped(cppID: "swiftcore/KitStudioPresenter::voicegroupNameAndMeta")
    let p = KitStudioPresenter()
    p.validateVoicegroupName = { (name: String) -> String? in
        name == "breakbeat_92_kit" || name == "new_kit" ? nil : "Voicegroup \(name) already exists in this project."
    }
    p.open()
    r.expect(p.voicegroupName.isEmpty && p.voicegroupNameInvalid, message: "open starts unnamed and unsaveable")
    r.expectEqual(expected: "0 slices · 0 bytes ROM", actual: p.metaText, what: "empty meta readout")
    p.applySuggestedVoicegroupName("new_kit")
    r.expect(
        p.voicegroupName == "new_kit" && !p.voicegroupNameInvalid && !p.voicegroupNameEdited,
        message: "suggested name applies cleanly")
    p.setVoicegroupName(name: "taken_kit")
    r.expect(p.voicegroupNameInvalid && p.voicegroupNameEdited, message: "taken name flags invalid and edited")
    p.applySuggestedVoicegroupName("new_kit")
    r.expectEqual(expected: "taken_kit", actual: p.voicegroupName, what: "suggestion never overrides a user choice")
    p.setVoicegroupName(name: "breakbeat_92_kit")
    p.toggleSnap()
    p.addSource(ImportedSample(buffer: [Float](repeating: 0.5, count: 128), sampleRate: 13379, suggestedName: "source"))
    p.insertMarker(frame: 10)
    p.insertMarker(frame: 100)
    let slice = p.sliceName(id: p.sliceId(row: 0))
    let autoMapped = p.metaText
    r.expect(
        autoMapped.hasPrefix("1 slice · ") && autoMapped.hasSuffix(" ROM") && autoMapped != "1 slice · 0 bytes ROM",
        message: "auto-placed slice contributes saved-at-rate ROM")
    p.dropSample(name: slice, onKey: 60)
    let mapped = p.metaText
    r.expect(
        mapped.hasPrefix("1 slice · ") && mapped.hasSuffix(" ROM") && mapped != "1 slice · 0 bytes ROM",
        message: "mapped slice contributes saved-at-rate ROM")
    p.dropSample(name: slice, onKey: 61)
    r.expectEqual(expected: mapped, actual: p.metaText, what: "one sample counts once across keys")
    r.expect(p.canSave, message: "mapped zone with valid name is saveable")
}
