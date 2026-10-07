import Foundation
import PorydawCore
import PorydawProject
import PorydawVoicegroup
import PorydawVoicegroupNative

internal let voicegroupEditingRowIDs: [String] = [
    "A001", "A003", "A004", "A005", "A006", "A007", "A008", "A009", "A010", "A011", "A012",
    "A013", "A014", "A015", "A016", "A017", "A018", "A019", "A020", "A021", "A022", "A023",
    "A024", "A025", "A026", "A027", "A028", "A029", "A030", "A031", "A032", "A033", "A034",
    "A035", "A036", "A037", "A038", "A039", "A040", "A041", "A042", "A043", "A044", "A045",
    "A046", "A047", "A048", "A049", "A050", "A051", "A052", "A053", "A054",
    "A057", "A058", "A059", "A060", "A061", "A062", "A063", "A064", "A065", "A066", "A067",
    "A068", "A069", "A070", "A071", "A072", "A073", "A074", "A075", "A076", "A077", "A078",
    "A079", "A080", "A081", "A082", "A083", "A084", "A085", "A093", "A094", "A095",
    "A096", "A097", "A098",
]

public func runVoicegroupEditingSuite(_ report: CheckReport) {
    editingBlankSlot(report)
    editingSparseInsertions(report)
    for family in 0..<7 {
        editingFamily(family, report)
    }
    editingDisplayNames(report)
    editingConfiguredBaselineAndSynth(report)
}

private func editingExpect(_ row: String, _ result: Bool, _ report: CheckReport, _ message: String) {
    report.expect(result, cppID: "voicegroupsourceediting/\(row)", message: message)
}

private func editingEqual<T: Equatable>(
    _ row: String, _ expected: T, _ actual: T,
    _ report: CheckReport, _ message: String
) {
    report.expectEqual(
        expected: expected, actual: actual, cppID: "voicegroupsourceediting/\(row)",
        what: message)
}

private func editingRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "voicegroup-editing-\(UUID().uuidString)", isDirectory: true)
}

private func openRichSource(at root: URL) throws -> VoicegroupSource {
    let source = VoicegroupSource()
    var error: String?
    guard source.open(projectRoot: root.path, voicegroupArg: "_fixture_rich", error: &error) else {
        throw EditingFixtureError.open(error ?? "unknown source error")
    }
    return source
}

private enum EditingFixtureError: Error {
    case open(String)
}

private func editingBlankSlot(_ report: CheckReport) {
    do {
        try withTempProjectCopy(prefix: "voicegroup-editing") { root in
            let source = try openRichSource(at: root)
            let baseline = editingLoad(root: root, name: source.loadName)
            editingExpect("A001", baseline != nil, report, "A001: fixture session opens source and native baseline")
            guard let baseline else { return }
            defer { voicegroup_free(baseline) }
            let slot = (0..<128).first { source.kindAt(slot: $0) == .none }
            editingExpect("A003", slot != nil, report, "A003: fixture_rich retains a materializable blank slot")
            guard let slot else { return }
            let before = source.sourceBytes()
            let created = VgVoice(macro: .square1, sustain: 15)
            let draft = source.voiceDraft(slot: slot, blank: created)
            editingExpect("A004", draft != nil, report, "A004: blank slot produces a draft")
            editingExpect("A005", draft?.materializesBlank == true, report, "A005: draft marks materialization")
            editingEqual("A006", created, draft?.voice, report, "A006: draft retains the requested voice")
            editingExpect("A007", source.setVoice(slot: slot, voice: created), report, "A007: blank slot accepts voice")
            editingEqual("A009", created, source.voiceAt(slot: slot), report, "A009: inserted voice equals request")
            editingExpect("A010", source.dirty, report, "A010: materialization marks source dirty")
            editingExpect("A011", source.restoreSourceBytes(before), report, "A011: original source bytes restore")
            editingEqual("A012", VgLineKind.none, source.kindAt(slot: slot), report, "A012: restored slot is empty")
            editingEqual("A013", before, source.sourceBytes(), report, "A013: restored bytes equal original")
            editingExpect("A014", !source.dirty, report, "A014: restoring pristine bytes clears dirty")
        }
    } catch {
        report.fail("voicegroupsourceediting/fixture", "blank fixture setup failed: \(error)")
    }
}

private func editingSparseInsertions(_ report: CheckReport) {
    let root = editingRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("sound/voicegroups", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        editingExpect(
            "A015", FileManager.default.fileExists(atPath: root.path), report,
            "A015: temporary directory is available")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        editingExpect(
            "A016", FileManager.default.fileExists(atPath: folder.path), report,
            "A016: sound/voicegroups directory exists")
        let path = folder.appendingPathComponent("sparse.inc")
        try Data("voice_group sparse, 36\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0\n".utf8).write(to: path)
        editingExpect(
            "A017", FileManager.default.fileExists(atPath: path.path), report,
            "A017: sparse source fixture is written")
        let source = VoicegroupSource()
        var error: String?
        let opened = source.open(projectRoot: root.path, voicegroupArg: "_sparse", error: &error)
        editingExpect("A018", opened, report, "A018: sparse source opens")
        if !opened { report.fail("voicegroupsourceediting/fixture", "sparse source open failed: \(error ?? "")") }
        guard opened, let original = source.voiceAt(slot: 36) else { return }
        let beforeFirst = VgVoice(macro: .square2, sustain: 15)
        let afterLast = VgVoice(macro: .noise, sustain: 15, release: 3)
        editingEqual("A019", VgLineKind.none, source.kindAt(slot: 12), report, "A019: slot 12 starts blank")
        editingEqual("A020", VgLineKind.none, source.kindAt(slot: 80), report, "A020: slot 80 starts blank")
        editingExpect("A021", source.setVoice(slot: 12, voice: beforeFirst), report, "A021: insert before first voice")
        editingEqual("A023", beforeFirst, source.voiceAt(slot: 12), report, "A023: slot 12 matches inserted voice")
        editingEqual("A025", original, source.voiceAt(slot: 36), report, "A025: original slot is unchanged")
        editingExpect("A026", source.setVoice(slot: 80, voice: afterLast), report, "A026: insert after last voice")
        editingEqual("A028", afterLast, source.voiceAt(slot: 80), report, "A028: slot 80 matches inserted voice")
        editingExpect("A029", try source.save(), report, "A029: sparse source saves")
        editingExpect("A030", !source.dirty, report, "A030: save clears dirty")
        let reloaded = VoicegroupSource()
        let reopened = reloaded.open(projectRoot: root.path, voicegroupArg: "_sparse", error: &error)
        editingExpect("A031", reopened, report, "A031: saved sparse source reopens")
        if !reopened {
            report.fail("voicegroupsourceediting/fixture", "saved sparse source reopen failed: \(error ?? "")")
        }
        guard reopened else { return }
        editingEqual("A033", beforeFirst, reloaded.voiceAt(slot: 12), report, "A033: slot 12 survives exactly")
        editingEqual("A035", original, reloaded.voiceAt(slot: 36), report, "A035: slot 36 survives exactly")
        editingEqual("A037", afterLast, reloaded.voiceAt(slot: 80), report, "A037: slot 80 survives exactly")
        let loaded = editingLoad(root: root, name: "sparse")
        editingExpect("A038", loaded != nil, report, "A038: native loader accepts saved sparse source")
        guard let loaded else { return }
        defer { voicegroup_free(loaded) }
        editingEqual(
            "A039", vgMacroVoiceType(.square2), editingTone(loaded, 12).type, report,
            "A039: inserted slot 12 loads as square 2")
        editingEqual(
            "A040", vgMacroVoiceType(.square1), editingTone(loaded, 36).type, report,
            "A040: original slot 36 loads as square 1")
        editingEqual(
            "A041", vgMacroVoiceType(.noise), editingTone(loaded, 80).type, report,
            "A041: inserted slot 80 loads as noise")
    } catch {
        report.fail("voicegroupsourceediting/fixture", "sparse fixture setup failed: \(error)")
    }
}

private func editingLoad(
    root: URL, name: String, config: UnsafePointer<VoicegroupLoaderConfig>? = nil
)
    -> UnsafeMutablePointer<LoadedVoiceGroup>?
{
    root.path.withCString { rootPath in
        name.withCString { loadName in voicegroup_load(rootPath, loadName, config) }
    }
}

private func editingTone(_ bank: UnsafeMutablePointer<LoadedVoiceGroup>, _ slot: Int) -> ToneData {
    withUnsafePointer(to: &bank.pointee.voices) {
        $0.withMemoryRebound(to: ToneData.self, capacity: 128) { $0[slot] }
    }
}

private func editingVoiceName(_ bank: UnsafeMutablePointer<LoadedVoiceGroup>, _ slot: Int) -> String {
    withUnsafePointer(to: &bank.pointee.voiceNames) {
        $0.withMemoryRebound(to: CChar.self, capacity: 128 * Int(VG_VOICE_NAME_LEN)) {
            String(cString: $0.advanced(by: slot * Int(VG_VOICE_NAME_LEN)))
        }
    }
}

private struct EditingSnapshot: Equatable {
    let type: UInt8
    let key: UInt8
    let panSweep: UInt8
    let attack: UInt8
    let decay: UInt8
    let sustain: UInt8
    let release: UInt8
    let name: String
    let packed: UInt
}

private func editingSnapshot(_ bank: UnsafeMutablePointer<LoadedVoiceGroup>, _ slot: Int) -> EditingSnapshot {
    let tone = editingTone(bank, slot)
    let cgb = tone.type & UInt8(VOICE_TYPE_CGB_MASK)
    let packed: UInt =
        (tone.type != UInt8(VOICE_KEYSPLIT) && tone.type != UInt8(VOICE_KEYSPLIT_ALL)
            && (cgb == UInt8(VOICE_SQUARE_1) || cgb == UInt8(VOICE_SQUARE_2) || cgb == UInt8(VOICE_NOISE)))
        ? UInt(bitPattern: tone.wavePointer) : 0
    return EditingSnapshot(
        type: tone.type, key: tone.key, panSweep: tone.panSweep,
        attack: tone.attack, decay: tone.decay, sustain: tone.sustain,
        release: tone.release, name: editingVoiceName(bank, slot), packed: packed)
}

private func editingLoaderVoiceName(_ symbol: String) -> String {
    let prefix = ["DirectSoundWaveData_", "ProgrammableWaveData_", "voicegroup_"]
        .first { symbol.hasPrefix($0) && symbol.count > $0.count }
    let text = prefix.map { String(symbol.dropFirst($0.count)) } ?? symbol
    return String(decoding: text.utf8.prefix(Int(VG_VOICE_NAME_LEN) - 1), as: UTF8.self)
}

private func editingResolvedTone(_ aggregate: ToneData, key: Int) -> ToneData? {
    guard (0..<128).contains(key) else { return nil }
    let tone: ToneData
    if aggregate.type & UInt8(VOICE_KEYSPLIT_ALL) != 0 {
        guard let subgroup = aggregate.subGroup?.assumingMemoryBound(to: ToneData.self) else { return nil }
        tone = subgroup[key]
    } else if aggregate.type & UInt8(VOICE_KEYSPLIT) != 0 {
        guard let subgroup = aggregate.subGroup?.assumingMemoryBound(to: ToneData.self),
            let table = aggregate.keySplitTable
        else { return nil }
        tone = subgroup[Int(table[key])]
    } else {
        tone = aggregate
    }
    return tone.type & (UInt8(VOICE_KEYSPLIT) | UInt8(VOICE_KEYSPLIT_ALL)) == 0 ? tone : nil
}

private func editingSameWave(
    _ left: UnsafeMutablePointer<WaveData>?,
    _ right: UnsafeMutablePointer<WaveData>?
) -> Bool {
    if left == right { return true }
    guard let left, let right else { return false }
    let a = left.pointee
    let b = right.pointee
    guard a.type == b.type, a.status == b.status, a.freq == b.freq,
        a.loopStart == b.loopStart, a.size == b.size
    else { return false }
    guard a.size > 0 else { return true }
    guard let lhs = a.data, let rhs = b.data else { return false }
    return UnsafeBufferPointer(start: lhs, count: Int(a.size))
        .elementsEqual(UnsafeBufferPointer(start: rhs, count: Int(b.size)))
}

private func editingSameResolvedTone(_ actual: ToneData, _ expected: ToneData, key: Int) -> Bool {
    guard let lhs = editingResolvedTone(actual, key: key),
        let rhs = editingResolvedTone(expected, key: key),
        lhs.type == rhs.type, lhs.key == rhs.key, lhs.length == rhs.length,
        lhs.panSweep == rhs.panSweep, lhs.attack == rhs.attack, lhs.decay == rhs.decay,
        lhs.sustain == rhs.sustain, lhs.release == rhs.release
    else { return false }
    let family = lhs.type & UInt8(VOICE_TYPE_CGB_MASK)
    if family == UInt8(VOICE_SQUARE_1) || family == UInt8(VOICE_SQUARE_2) || family == UInt8(VOICE_NOISE) {
        return lhs.wavePointer == rhs.wavePointer
    }
    if family == UInt8(VOICE_PROGRAMMABLE_WAVE) {
        guard let left = lhs.wavePointer, let right = rhs.wavePointer else {
            return lhs.wavePointer == rhs.wavePointer
        }
        return UnsafeBufferPointer(start: UnsafeRawPointer(left).assumingMemoryBound(to: UInt8.self), count: 16)
            .elementsEqual(
                UnsafeBufferPointer(
                    start: UnsafeRawPointer(right).assumingMemoryBound(to: UInt8.self), count: 16))
    }
    return editingSameWave(lhs.wav, rhs.wav)
}

private func editingFirstSlot(_ source: VoicegroupSource, where matches: (VgMacro) -> Bool) -> Int? {
    (0..<128).first { slot in source.voiceAt(slot: slot).map { matches($0.macro) } ?? false }
}

private func editingSameVoiceFields(_ actual: VgVoice?, _ expected: VgVoice) -> Bool {
    guard let actual, actual.macro == expected.macro else { return false }
    switch expected.macro {
    case .keysplit:
        return actual.symbol == expected.symbol && actual.keysplitTable == expected.keysplitTable
    case .keysplitAll:
        return actual.symbol == expected.symbol
    default:
        return actual.key == expected.key && actual.pan == expected.pan && actual.symbol == expected.symbol
            && actual.sweep == expected.sweep && actual.duty == expected.duty && actual.period == expected.period
            && actual.attack == expected.attack && actual.decay == expected.decay && actual.sustain == expected.sustain
            && actual.release == expected.release
    }
}

private func editingChangedLineCount(_ before: Data, _ after: Data) -> Int {
    let old = before.split(separator: 10, omittingEmptySubsequences: false)
    let new = after.split(separator: 10, omittingEmptySubsequences: false)
    guard old.count == new.count else { return -1 }
    return zip(old, new).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
}

private func editingFamily(_ family: Int, _ report: CheckReport) {
    do {
        try withTempProjectCopy(prefix: "voicegroup-editing") { root in
            let source = try openRichSource(at: root)
            let file = URL(filePath: source.filePath)
            let before = try Data(contentsOf: file)
            let baseline = editingLoad(root: root, name: source.loadName)
            editingExpect("A042", baseline != nil, report, "A042: fixture session opens source and native baseline")
            guard let baseline else { return }
            defer { voicegroup_free(baseline) }
            let drumkits = VoicegroupSource.drumkitInstruments(root.path)
            if family >= 5 {
                editingExpect("A049", drumkits.count >= 2, report, "A049: fixture retains two drumkit definitions")
                guard drumkits.count >= 2 else { return }
            }
            var slot: Int
            var edited: VgVoice
            switch family {
            case 0:
                let found = editingFirstSlot(source) {
                    $0 == .directSound || $0 == .directSoundNoResample || $0 == .directSoundAlt
                }
                editingExpect("A043", found != nil, report, "A043: fixture retains a DirectSound voice")
                guard let found, var voice = source.voiceAt(slot: found) else { return }
                slot = found
                voice.key = 61
                voice.attack = 200
                voice.decay = 100
                voice.sustain = 50
                voice.release = 25
                let donor = source.voiceAt(slot: 1)
                editingExpect("A044", donor != nil, report, "A044: fixture retains donor at slot 1")
                guard let donor else { return }
                voice.symbol = donor.symbol
                edited = voice
            case 1:
                let found = editingFirstSlot(source) { $0 == .square1 || $0 == .square1Alt }
                editingExpect("A045", found != nil, report, "A045: fixture retains a square-1 voice")
                guard let found, var voice = source.voiceAt(slot: found) else { return }
                slot = found
                voice.duty = 3
                voice.sustain = 15
                voice.sweep = 7
                edited = voice
            case 2:
                let found = editingFirstSlot(source) { $0 == .noise || $0 == .noiseAlt }
                editingExpect("A046", found != nil, report, "A046: fixture retains a noise voice")
                guard let found, var voice = source.voiceAt(slot: found) else { return }
                slot = found
                voice.period = 1 - (voice.period & 1)
                edited = voice
            case 3:
                let found = editingFirstSlot(source) { $0 == .progWave || $0 == .progWaveAlt }
                editingExpect("A047", found != nil, report, "A047: fixture retains a programmable-wave voice")
                guard let found, var voice = source.voiceAt(slot: found) else { return }
                slot = found
                voice.release = (voice.release & 7) == 5 ? 6 : 5
                edited = voice
            case 4:
                let found = editingFirstSlot(source) { $0 == .keysplit }
                let donor = found.flatMap { source.voiceAt(slot: $0 + 1) }
                editingExpect(
                    "A048", found != nil && donor?.macro == .keysplit, report,
                    "A048: fixture retains adjacent keysplit voices")
                guard let found, let donor, var voice = source.voiceAt(slot: found) else { return }
                slot = found
                voice.symbol = donor.symbol
                voice.keysplitTable = donor.keysplitTable
                edited = voice
            case 5:
                let found = editingFirstSlot(source) { $0 == .keysplitAll }
                editingExpect("A050", found != nil, report, "A050: fixture retains a drumkit aggregate")
                guard let found, var voice = source.voiceAt(slot: found) else { return }
                slot = found
                voice.symbol = drumkits[drumkits.count - 1]
                edited = voice
            default:
                slot = 4
                editingExpect(
                    "A051", source.voiceAt(slot: slot) != nil, report,
                    "A051: conversion slot 4 is populated")
                edited = VgVoice(macro: .keysplitAll, symbol: drumkits[0])
            }
            var aggregateOracleSlot = family == 4 ? slot + 1 : -1
            if family >= 5 {
                aggregateOracleSlot =
                    (0..<128).first { index in
                        index != slot && source.voiceAt(slot: index)?.macro == .keysplitAll
                            && source.voiceAt(slot: index)?.symbol == edited.symbol
                    } ?? -1
                editingExpect(
                    "A052", aggregateOracleSlot >= 0, report,
                    "A052: selected drumkit has an existing aggregate")
            }
            let expectedName =
                family == 0
                ? editingVoiceName(baseline, 1)
                : (family == 4
                    ? editingVoiceName(baseline, slot + 1)
                    : (family >= 5 ? editingLoaderVoiceName(edited.symbol) : editingVoiceName(baseline, slot)))
            editingExpect("A053", source.setVoice(slot: slot, voice: edited), report, "A053: edited voice is accepted")
            editingExpect("A054", source.dirty, report, "A054: edited voice makes source dirty")
            let store = try VoicegroupStore(projectRoot: root.path)
            let preview = try? BankBuilder(inputs: store.bankBuildInputs()).build(
                source.descriptors(),
                at: VoicegroupLocation(filePath: source.filePath, sectionLabel: source.sectionLabel))
            editingExpect("A057", preview != nil, report, "A057: Swift builder accepts edited preview")
            guard let preview else { return }
            editingEqual(
                "A058", expectedName, preview.name(at: slot), report,
                "A058: preview resolves edited display name")
            editingEqual(
                "A059", vgMacroVoiceType(edited.macro), preview.voices[slot].type, report,
                "A059: preview loads the edited voice type")
            if family >= 4 {
                if aggregateOracleSlot >= 0 {
                    editingExpect(
                        "A060",
                        editingSameResolvedTone(
                            preview.voices[slot], editingTone(baseline, aggregateOracleSlot),
                            key: family >= 5 ? 36 : 60), report,
                        "A060: preview aggregate resolves the same playable child as existing aggregate")
                } else {
                    report.fail(
                        "voicegroupsourceediting/fixture",
                        "preview aggregate has no baseline oracle slot")
                }
            }
            editingExpect(
                "A061", editingSameVoiceFields(source.voiceAt(slot: slot), edited), report,
                "A061: edited source retains the requested family fields")
            editingEqual(
                "A062", before, try Data(contentsOf: file), report,
                "A062: preview does not modify the original file")
            editingExpect("A063", try source.save(), report, "A063: edited source saves")
            editingExpect("A064", !source.dirty, report, "A064: save clears dirty")
            editingEqual(
                "A065", 1, editingChangedLineCount(before, try Data(contentsOf: file)), report,
                "A065: saving the edit changes exactly one source line")
            let reloaded = editingLoad(root: root, name: source.loadName)
            editingExpect("A066", reloaded != nil, report, "A066: saved source loads as native bank")
            guard let reloaded else { return }
            defer { voicegroup_free(reloaded) }
            let tone = editingTone(reloaded, slot)
            editingEqual(
                "A067", vgMacroVoiceType(edited.macro), tone.type, report,
                "A067: saved bank retains edited native voice type")
            if family >= 4 {
                editingExpect("A068", tone.subGroup != nil, report, "A068: aggregate has a subgroup")
                if family == 4 {
                    editingExpect("A069", tone.keySplitTable != nil, report, "A069: keysplit retains lookup table")
                }
                if aggregateOracleSlot >= 0 {
                    editingExpect(
                        "A070",
                        editingSameResolvedTone(
                            tone, editingTone(baseline, aggregateOracleSlot),
                            key: family >= 5 ? 36 : 60), report,
                        "A070: saved aggregate resolves unchanged child")
                } else {
                    report.fail(
                        "voicegroupsourceediting/fixture",
                        "saved aggregate has no baseline oracle slot")
                }
            } else {
                editingEqual("A071", UInt8(truncatingIfNeeded: edited.key), tone.key, report, "A071: native key")
                editingEqual(
                    "A072", UInt8(truncatingIfNeeded: edited.attack), tone.attack, report, "A072: native attack")
                editingEqual("A073", UInt8(truncatingIfNeeded: edited.decay), tone.decay, report, "A073: native decay")
                editingEqual(
                    "A074", UInt8(truncatingIfNeeded: edited.sustain), tone.sustain, report, "A074: native sustain")
                editingEqual(
                    "A075", UInt8(truncatingIfNeeded: edited.release), tone.release, report, "A075: native release")
                if family == 0 || family == 3 {
                    editingEqual(
                        "A076", edited.pan == 0 ? UInt8(0) : UInt8(0x80 | edited.pan),
                        tone.panSweep, report, "A076: native sample/wave pan flags")
                }
                if family == 1 {
                    editingEqual(
                        "A077", UInt8(truncatingIfNeeded: edited.sweep), tone.panSweep,
                        report, "A077: square sweep packing")
                    editingEqual(
                        "A078", UInt(edited.duty & 0x03), UInt(bitPattern: tone.wavePointer),
                        report, "A078: square duty packing")
                } else if family == 2 {
                    editingEqual(
                        "A079", UInt(edited.period & 0x01), UInt(bitPattern: tone.wavePointer),
                        report, "A079: noise period packing")
                }
            }
            editingEqual(
                "A080", expectedName, editingVoiceName(reloaded, slot), report,
                "A080: saved bank resolves edited display name")
            for untouched in 0..<128 where untouched != slot {
                editingEqual(
                    "A081", editingSnapshot(baseline, untouched), editingSnapshot(reloaded, untouched),
                    report, "A081: every unedited native slot remains equal to the baseline")
            }
            let roundTrip = VoicegroupSource()
            var error: String?
            let opened = roundTrip.open(projectRoot: root.path, voicegroupArg: "_fixture_rich", error: &error)
            editingExpect("A082", opened, report, "A082: saved edited source reopens")
            if !opened {
                report.fail("voicegroupsourceediting/fixture", "saved edited source reopen failed: \(error ?? "")")
            }
            guard opened else { return }
            editingExpect("A083", !roundTrip.dirty, report, "A083: freshly opened source is pristine")
            editingExpect(
                "A085", editingSameVoiceFields(roundTrip.voiceAt(slot: slot), edited), report,
                "A085: edited voice family fields survive save and reopen")
        }
    } catch {
        report.fail("voicegroupsourceediting/fixture", "family \(family) fixture failed: \(error)")
    }
}

private func editingConfiguredBaselineAndSynth(_ report: CheckReport) {
    let baselineID = "voicegroupsourceediting/VoicegroupEditingChecks::configuredBaseline"
    let synthID = "voicegroupsourceediting/VoicegroupEditingChecks::synthDescriptor"
    do {
        try withTempProjectCopy(prefix: "voicegroup-editing-synth") { root in
            let midi = root.appendingPathComponent("sound/songs/midi/mus_gym.mid")
            try FileManager.default.createDirectory(
                at: midi.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data([
                0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0, 96,
                0x4d, 0x54, 0x72, 0x6b, 0, 0, 0, 4, 0, 0xff, 0x2f, 0,
            ]).write(to: midi)
            let project = ProjectStore(projectRoot: root)
            let opened = awaitValue { try await project.open() }
            let song = awaitValue { try await project.songMeta(label: "mus_gym") }
            guard case .success(let snapshot)? = opened,
                case .success(let info)? = song
            else {
                report.fail(baselineID, "mus_gym metadata could not be read")
                return
            }
            let bank = try VoicegroupStore(projectRoot: root.path)
                .loadBank(voicegroupArg: info.cfg.voicegroupArgument)
            report.expect(
                snapshot.isOpen && info.isPlayable && info.cfg.voicegroupArgument == "_fixture_rich"
                    && bank.loadName == "fixture_rich" && bank.slotViews[0].voice != nil,
                cppID: baselineID,
                message: "the song's configured voicegroup argument resolves and loads the baseline bank")

            let source = try openRichSource(at: root)
            let slot = (0..<128).first { index in
                guard let macro = source.voiceAt(slot: index)?.macro else { return false }
                return macro == .directSound || macro == .directSoundNoResample || macro == .directSoundAlt
            }
            guard let slot, var voice = source.voiceAt(slot: slot) else {
                report.fail(synthID, "rich bank has no DirectSound voice")
                return
            }
            let synth = root.appendingPathComponent("sound/direct_sound_synth_data.inc")
            try Data("VgcheckSynthPulse::\n\tset_synth_pulse 0x21, 0x43, 0x65, 0x87\n".utf8).write(to: synth)
            voice.symbol = "VgcheckSynthPulse"
            guard source.setVoice(slot: slot, voice: voice), try source.save(),
                let loaded = editingLoad(root: root, name: source.loadName)
            else {
                report.fail(synthID, "edited synth voice failed to save or reload")
                return
            }
            defer { voicegroup_free(loaded) }
            let tone = editingTone(loaded, slot)
            let bytes = tone.wav?.pointee.data.map { data in
                (2...5).map { UInt8(bitPattern: data[$0]) }
            }
            report.expect(
                tone.type & ~UInt8(0x18) == 0 && tone.wav?.pointee.size == 0 && bytes == [0x21, 0x43, 0x65, 0x87],
                cppID: synthID,
                message: "a saved synth descriptor loads through the voicegroup with its packed parameters")
            report.expect(
                tone.wav?.pointee.data.map { UInt8(bitPattern: $0[1]) } == 0,
                cppID: synthID,
                message: "a saved synth descriptor loads with its zero waveform byte")
        }
    } catch {
        report.fail(baselineID, "configured baseline or synth fixture failed: \(error)")
    }
}

private func editingDisplayNames(_ report: CheckReport) {
    editingEqual(
        "A093", "Sample", vgMacroDisplayName(.directSound), report,
        "A093: DirectSound display name")
    editingEqual(
        "A094", "Sample (fixed pitch)", vgMacroDisplayName(.directSoundNoResample), report,
        "A094: fixed-pitch sample display name")
    editingEqual(
        "A095", "Sample (reverse)", vgMacroDisplayName(.directSoundAlt), report,
        "A095: reverse sample display name")
    editingEqual(
        "A096", "Sample (fixed pitch)", m4aVoiceTypeName(UInt8(VOICE_DIRECTSOUND_NO_RESAMPLE)),
        report, "A096: native fixed-pitch sample type name")
    editingEqual(
        "A097", "Sample (reverse)", m4aVoiceTypeName(UInt8(VOICE_DIRECTSOUND_ALT)),
        report, "A097: native reverse sample type name")
    editingEqual(
        "A098", "Sample", m4aVoiceTypeName(UInt8(VOICE_KEYSPLIT)),
        report, "A098: native keysplit voice type name")
}
