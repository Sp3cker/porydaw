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
    editingStoreKit(report)
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
    guard let tableOffset: Int = MemoryLayout<LoadedVoiceGroup>.offset(of: \.voiceNames) else {
        preconditionFailure("LoadedVoiceGroup.voiceNames has no stored offset; header/build mismatch.")
    }
    let nameLength: Int = Int(VG_VOICE_NAME_LEN)
    let offset: Int = tableOffset + slot * nameLength
    let characters: UnsafePointer<CChar> = UnsafeRawPointer(bank).advanced(by: offset)
        .assumingMemoryBound(to: CChar.self)
    return String(cString: characters)
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
    let isSplit: Bool
    switch tone.type {
    case UInt8(VOICE_KEYSPLIT), UInt8(VOICE_KEYSPLIT_ALL): isSplit = true
    default: isSplit = false
    }
    let isPacked: Bool
    switch cgb {
    case UInt8(VOICE_SQUARE_1), UInt8(VOICE_SQUARE_2), UInt8(VOICE_NOISE): isPacked = true
    default: isPacked = false
    }
    let packed: UInt = !isSplit && isPacked ? UInt(bitPattern: tone.wavePointer) : 0
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
    let aggregateMask: UInt8 = UInt8(VOICE_KEYSPLIT) | UInt8(VOICE_KEYSPLIT_ALL)
    let isAggregate: Bool = tone.type & aggregateMask != 0
    return isAggregate ? nil : tone
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
                let found = editingFirstSlot(source) { (macro: VgMacro) -> Bool in
                    switch macro {
                    case .directSound, .directSoundNoResample, .directSoundAlt: return true
                    default: return false
                    }
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
            let midiBytes: [UInt8] = [
                0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0, 96,
                0x4d, 0x54, 0x72, 0x6b, 0, 0, 0, 4, 0, 0xff, 0x2f, 0,
            ]
            try Data(midiBytes).write(to: midi)
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
            let slot = (0..<128).first { (index: Int) -> Bool in
                guard let macro = source.voiceAt(slot: index)?.macro else { return false }
                switch macro {
                case .directSound, .directSoundNoResample, .directSoundAlt: return true
                default: return false
                }
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

private func editingStoreKit(_ report: CheckReport) {
    let id = "swiftcore/VoicegroupStoreKitEdit::"
    do {
        try withTempProjectCopy(prefix: "voicegroup-kit-editing") { root in
            let parentPath = root.appendingPathComponent("sound/voicegroups/fixture_rich.inc").path
            let childPath = root.appendingPathComponent("sound/voicegroups/fixture_drums_a.inc").path
            let tablePath = root.appendingPathComponent("sound/keysplit_tables.inc").path
            let otherPath = root.appendingPathComponent("sound/voicegroups/fixture_other.inc").path
            try ProjectFileStore.write(
                otherPath, data: Data("voice_group fixture_other\n\tvoice_keysplit_all fixture_drums_a\n".utf8))
            try VoicegroupSource.appendIncludeLine(projectRoot: root.path, name: "fixture_other")
            let store = try VoicegroupStore(projectRoot: root.path)
            let before = try store.loadBank(voicegroupArg: "_fixture_rich")
            let other = try store.loadBank(voicegroupArg: "_fixture_other")
            guard let expected = before.slotViews[10].voice else {
                report.fail(id + "fixture", "fixture slot 10 has no parent")
                return
            }
            var children = [VgVoice?](repeating: nil, count: 128)
            children[36] = VgVoice(macro: .square2, key: 62, attack: 3, decay: 2, sustain: 11, release: 4)
            children[37] = VgVoice(macro: .noise, key: 63, period: 1, attack: 2, decay: 2, sustain: 10, release: 3)
            let parent = VgVoice(macro: .keysplitAll, symbol: "fixture_drums_a")
            let drumEdit = KitEditInput(
                id: before.id, slot: 10, parent: parent, subgroupSymbol: "fixture_drums_a",
                children: children, table: nil)
            let tableBefore = try ProjectFileStore.read(tablePath)
            let paths = [parentPath, childPath, tablePath]
            let beforeDrumEdit = try paths.map { try ProjectFileStore.read($0) }
            let drumResult = try store.applyKitEdit(input: drumEdit, expected: .parent(expected))
            guard case .applied(let drum) = drumResult else {
                report.fail(id + "drumkit", "drumkit edit was not applied")
                return
            }
            let afterDrumApply = try paths.map { try ProjectFileStore.read($0) }
            report.expectEqual(
                expected: beforeDrumEdit, actual: afterDrumApply,
                cppID: id + "drumkit-staged", what: "drumkit apply writes no files")
            report.expect(
                drum.view.bank !== before.bank && drum.view.dirty
                    && drum.materialization == nil && drum.materializationToken == nil,
                cppID: id + "republish", message: "kit publishes a new dirty bank without materialization")
            report.expect(
                store.currentPublication(id: other.id)?.bank === other.bank,
                cppID: id + "bound-only", message: "other referencing voicegroup keeps its prior publication")
            let drumLease = ProjectBankLease(
                bank: drum.view.bank, view: drum.view, publicationOwner: UUID(), publicationRevision: 1)
            report.expectEqual(
                expected: VgMacro.square2.rawValue, actual: drumLease.subvoiceMacros(at: 10)?[36],
                cppID: id + "drumkit-bank", what: "dirty bank resolves the staged drum child")
            let rebound = try store.rebind()
            if let otherView = rebound.first(where: { $0.id == other.id }) {
                let otherLease = ProjectBankLease(
                    bank: otherView.bank, view: otherView, publicationOwner: UUID(), publicationRevision: 1)
                report.expectEqual(
                    expected: VgMacro.square2.rawValue, actual: otherLease.subvoiceMacros(at: 0)?[36],
                    cppID: id + "rebind-overlay", what: "another record rebuild sees the global staged subgroup")
            } else {
                report.fail(id + "rebind-overlay", "other referencing bank did not rebuild")
            }
            guard let savedDrum = try store.saveVoicegroup(id: before.id) else {
                report.fail(id + "drumkit-save", "drumkit save was superseded")
                return
            }
            report.expect(
                !savedDrum.dirty, cppID: id + "drumkit-save", message: "normal save publishes the kit clean")
            let reopened = try openRichSource(at: root)
            report.expectEqual(
                expected: parent, actual: reopened.voiceAt(slot: 10),
                cppID: id + "parent", what: "saved parent line matches drumkit input")
            let childSource = reopened
            var error: String?
            let childOpened = childSource.open(
                location: VoicegroupLocation(filePath: childPath, sectionLabel: "fixture_drums_a"), error: &error)
            report.expect(childOpened, cppID: id + "child-open", message: error ?? "saved subgroup opens")
            guard childOpened else { return }
            report.expectEqual(
                expected: children[36], actual: childSource.voiceAt(slot: 36),
                cppID: id + "children", what: "child arguments were saved")
            report.expect(
                childSource.projectRoot.isEmpty && childSource.voicegroupArg.isEmpty,
                cppID: id + "location-identity", message: "reused source adopts the exact-location opener")
            let childSaved = try childSource.save()
            report.expect(
                childSaved, cppID: id + "location-save",
                message: "location-opened source saves through its exact recorded location")
            let childText = String(decoding: try ProjectFileStore.read(childPath), as: UTF8.self)
            report.expect(
                childText.contains(kitBlankChildLine + "\n"),
                cppID: id + "blank-line", message: "nil children write the shared blank template")
            report.expectEqual(
                expected: VgVoice(macro: .square1, sustain: 15), actual: childSource.voiceAt(slot: 0),
                cppID: id + "blank-voice", what: "unassigned key parses as the blank template voice")
            let tableAfterDrumEdit = try ProjectFileStore.read(tablePath)
            report.expectEqual(
                expected: tableBefore, actual: tableAfterDrumEdit,
                cppID: id + "drumkit-table", what: "drumkit edit does not touch keysplit table")

            children[37] = VgVoice(macro: .noise, key: 65, period: 0, attack: 4, decay: 2, sustain: 8, release: 5)
            let values = (0..<128).map { (note: Int) -> UInt8 in note < 64 ? 36 : 37 }
            let table = KeysplitTable(name: "keysplit_fixture", startingNote: 0, maxNote: 128, table: values)
            let splitParent = VgVoice(macro: .keysplit, symbol: "fixture_drums_a", keysplitTable: table.name)
            let splitEdit = KitEditInput(
                id: before.id, slot: 10, parent: splitParent, subgroupSymbol: "fixture_drums_a",
                children: children, table: table)
            let beforeSplitEdit = try paths.map { try ProjectFileStore.read($0) }
            let splitResult = try store.applyKitEdit(input: splitEdit, expected: .parent(parent))
            guard case .applied(let split) = splitResult else {
                report.fail(id + "keysplit", "keysplit edit was not applied")
                return
            }
            let afterSplitApply = try paths.map { try ProjectFileStore.read($0) }
            report.expectEqual(
                expected: beforeSplitEdit, actual: afterSplitApply,
                cppID: id + "keysplit-staged", what: "keysplit apply writes no parent, subgroup or table bytes")
            report.expect(split.view.dirty, cppID: id + "keysplit-dirty", message: "keysplit apply publishes dirty")
            let inputs = try store.bankBuildInputs()
            report.expectEqual(
                expected: table, actual: inputs.keysplits.table(named: table.name),
                cppID: id + "picker-table-overlay", what: "shared build inputs prefer the staged table")
            let stagedKit = try store.kitSnapshot(id: before.id, slot: 10)
            report.expect(
                stagedKit?.parent == splitParent && stagedKit?.subgroupSymbol == "fixture_drums_a"
                    && stagedKit?.children.count == 128 && stagedKit?.children[36] == children[36]
                    && stagedKit?.children[37] == children[37] && stagedKit?.table == table,
                cppID: id + "kitSnapshot-staged", message: "kit reader sees raw staged children and table before save")
            let splitLease = ProjectBankLease(
                bank: split.view.bank, view: split.view, publicationOwner: UUID(), publicationRevision: 2)
            report.expectEqual(
                expected: VgMacro.square2.rawValue, actual: splitLease.subvoiceMacros(at: 10)?[0],
                cppID: id + "keysplit-bank-low", what: "republished table routes lower keys to child 36")
            report.expectEqual(
                expected: VgMacro.noise.rawValue, actual: splitLease.subvoiceMacros(at: 10)?[127],
                cppID: id + "keysplit-bank-high", what: "republished table routes upper keys to child 37")
            let snapshot = try paths.map { try ProjectFileStore.read($0) }
            do {
                let unblock = try WriteFailureFixture.blockAtomicWrites(to: childPath)
                defer { unblock() }
                do {
                    _ = try store.saveVoicegroup(id: before.id)
                    report.fail(id + "save-failure", "unwritable subgroup save succeeded")
                } catch let error as VoicegroupStoreError {
                    report.expect(
                        error.localizedDescription.contains(childPath)
                            || error.localizedDescription.contains(parentPath),
                        cppID: id + "save-failure", message: "failed save names the blocked source")
                }
                let afterFailedSave = try paths.map { try ProjectFileStore.read($0) }
                report.expectEqual(
                    expected: snapshot, actual: afterFailedSave,
                    cppID: id + "save-atomicity", what: "failed multi-file save restores every file")
                report.expect(
                    store.currentPublication(id: before.id)?.dirty == true
                        && store.currentPublication(id: before.id)?.bank === split.view.bank,
                    cppID: id + "save-retains-staging", message: "failed save preserves dirty publication")
                let failedInputs = try store.bankBuildInputs()
                report.expectEqual(
                    expected: table, actual: failedInputs.keysplits.table(named: table.name),
                    cppID: id + "save-retains-table", what: "failed save retains staged table")
            }
            guard let savedSplit = try store.saveVoicegroup(id: before.id) else {
                report.fail(id + "keysplit-save", "keysplit save was superseded")
                return
            }
            report.expect(
                !savedSplit.dirty, cppID: id + "keysplit-save", message: "successful retry publishes clean")
            let savedTable = try KeysplitTables.parse(files: [tablePath]).table(named: table.name)?.table
            report.expectEqual(
                expected: values, actual: savedTable,
                cppID: id + "keysplit-table", what: "normal song save writes the staged table")
            let savedParent = try openRichSource(at: root)
            report.expectEqual(
                expected: splitParent, actual: savedParent.voiceAt(slot: 10),
                cppID: id + "keysplit-parent", what: "normal song save writes the staged parent")
            let savedChildren = VoicegroupSource()
            var savedChildError: String?
            guard
                savedChildren.open(
                    location: VoicegroupLocation(filePath: childPath, sectionLabel: "fixture_drums_a"),
                    error: &savedChildError)
            else {
                report.fail(id + "keysplit-children", savedChildError ?? "saved subgroup does not open")
                return
            }
            report.expectEqual(
                expected: children[37], actual: savedChildren.voiceAt(slot: 37),
                cppID: id + "keysplit-children", what: "saved subgroup reparses the high-key child")
            let savedSnapshot = try paths.map { try ProjectFileStore.read($0) }
            report.expect(
                zip(beforeSplitEdit, savedSnapshot).allSatisfy { $0.0 != $0.1 },
                cppID: id + "keysplit-files", message: "normal save writes the parent, subgroup and table edits")
            do {
                _ = try store.applyKitEdit(input: drumEdit, expected: .parent(expected))
                report.fail(id + "conflict", "stale parent was accepted")
            } catch let error as VoicegroupStoreError {
                report.expect(
                    error.localizedDescription.contains(parentPath),
                    cppID: id + "conflict", message: "conflict names parent file")
            }
            let afterConflict = try paths.map { try ProjectFileStore.read($0) }
            report.expectEqual(
                expected: savedSnapshot, actual: afterConflict,
                cppID: id + "conflict-atomicity", what: "stale expected parent changes no file")
            var missing = drumEdit
            missing.parent?.symbol = "missing_kit_symbol"
            missing.subgroupSymbol = "missing_kit_symbol"
            do {
                _ = try store.applyKitEdit(input: missing, expected: .parent(splitParent))
                report.fail(id + "missing-subgroup", "missing subgroup was accepted")
            } catch let error as VoicegroupStoreError {
                report.expect(
                    error.localizedDescription.contains("no sub-voicegroup missing_kit_symbol found in the project"),
                    cppID: id + "missing-subgroup", message: "missing subgroup has a named refusal")
            }
            let afterMissingSubgroup = try paths.map { try ProjectFileStore.read($0) }
            report.expectEqual(
                expected: savedSnapshot, actual: afterMissingSubgroup,
                cppID: id + "missing-atomicity", what: "missing subgroup changes no file")
            report.expect(
                store.currentPublication(id: before.id)?.bank === savedSplit.bank
                    && store.currentPublication(id: before.id)?.dirty == false,
                cppID: id + "refusal-publication", message: "invalid kit edits stage nothing and retain publication")

            let parentRestore = KitEditInput(
                id: before.id, slot: 10, parent: parent, subgroupSymbol: "", children: [], table: nil)
            _ = try store.applyKitEdit(input: parentRestore, expected: .parent(splitParent))
            _ = try store.saveVoicegroup(id: before.id)
            let scalar = VgVoice(macro: .square2, key: 67, attack: 2, decay: 2, sustain: 9, release: 3)
            let scalarRestore = KitEditInput(
                id: before.id, slot: 10, parent: scalar, subgroupSymbol: "", children: [], table: nil)
            let beforeScalar = try paths.map { try ProjectFileStore.read($0) }
            let parentBeforeScalar = store.currentPublication(id: before.id)?.slotViews[10].voice
            let overlayTimes = try [childPath, tablePath].map {
                try FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date
            }
            let scalarResult = try store.applyKitEdit(input: scalarRestore, expected: .authoritative)
            guard case .applied(let scalarEdit) = scalarResult else {
                report.fail(id + "parent-only", "authoritative scalar restore did not apply")
                return
            }
            report.expect(
                scalarEdit.view.dirty && scalarEdit.view.slotViews[10].voice == scalar,
                cppID: id + "parent-only", message: "parent-only edit replaces a keysplit-all parent in memory")
            report.expect(
                parentBeforeScalar == parent && parentBeforeScalar != splitParent
                    && scalarEdit.view.slotViews[10].voice == scalar,
                cppID: id + "authoritative-parent", message: "nil expected parent applies over a changed parent")
            let afterScalarApply = try paths.map { try ProjectFileStore.read($0) }
            report.expectEqual(
                expected: beforeScalar, actual: afterScalarApply,
                cppID: id + "parent-only-staged", what: "scalar restore writes no files during apply")
            guard let savedScalar = try store.saveVoicegroup(id: before.id) else {
                report.fail(id + "parent-only-save", "scalar restore save was superseded")
                return
            }
            let afterScalarSave = try paths.map { try ProjectFileStore.read($0) }
            let savedOverlayTimes = try [childPath, tablePath].map {
                try FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date
            }
            report.expect(
                !savedScalar.dirty && beforeScalar[0] != afterScalarSave[0]
                    && beforeScalar[1] == afterScalarSave[1] && beforeScalar[2] == afterScalarSave[2],
                cppID: id + "parent-only-save", message: "parent-only save writes only the parent and publishes clean")
            report.expectEqual(
                expected: overlayTimes, actual: savedOverlayTimes,
                cppID: id + "parent-only-no-overlays", what: "parent-only save does not rewrite subgroup or table files"
            )
            let scalarOnDisk = try openRichSource(at: root)
            report.expectEqual(
                expected: scalar, actual: scalarOnDisk.voiceAt(slot: 10),
                cppID: id + "parent-only-reparse", what: "saved scalar parent reparses exactly")
            try editingUndefinedKit(report, root: root)
        }
    } catch {
        report.fail(id + "fixture", "kit-edit checks: \(error)")
    }
}

private func editingUndefinedKit(_ report: CheckReport, root: URL) throws {
    let id = "swiftcore/VoicegroupStoreKitEdit::"
    let parentPath = root.appendingPathComponent("sound/voicegroups/fixture_rich.inc").path
    let childPath = root.appendingPathComponent("sound/voicegroups/fixture_drums_a.inc").path
    let paths = [parentPath, childPath]
    let diskBefore = try paths.map { try ProjectFileStore.read($0) }
    let store = try VoicegroupStore(projectRoot: root.path)
    let before = try store.loadBank(voicegroupArg: "_fixture_rich")
    let parent = VgVoice(macro: .keysplitAll, symbol: "fixture_drums_a")
    let child = VgVoice(macro: .square2, key: 67, pan: 17, duty: 9, attack: 9, sustain: 15)
    var children = [VgVoice?](repeating: nil, count: 128)
    children[0] = child
    let edit = KitEditInput(
        id: before.id, slot: 127, parent: parent, subgroupSymbol: parent.symbol,
        children: children, table: nil)
    var staleEmpty = edit
    staleEmpty.slot = 10
    let priorKit = try store.kitSnapshot(id: before.id, slot: 10)
    do {
        _ = try store.applyKitEdit(input: staleEmpty, expected: .parent(nil))
        report.fail(id + "undefined-slot-conflict", "undefined precondition overwrote a defined slot")
    } catch let error as VoicegroupStoreError {
        report.expect(
            error.localizedDescription.contains("parent changed"),
            cppID: id + "undefined-slot-conflict", message: "undefined precondition refuses a defined slot")
    }
    let unchangedKit = try store.kitSnapshot(id: before.id, slot: 10)
    let conflictDisk = try paths.map { try ProjectFileStore.read($0) }
    report.expect(
        store.currentPublication(id: before.id)?.bank === before.bank
            && store.currentPublication(id: before.id)?.dirty == before.dirty
            && unchangedKit == priorKit && conflictDisk == diskBefore,
        cppID: id + "undefined-slot-conflict", message: "undefined precondition conflict stages and publishes nothing")
    guard case .applied(let applied) = try store.applyKitEdit(input: edit, expected: .parent(nil)),
        let materialization = applied.materialization
    else {
        report.fail(id + "undefined-slot", "undefined slot did not return its materialization")
        return
    }
    let staged = try store.kitSnapshot(id: before.id, slot: 127)
    let unchanged = try paths.map { try ProjectFileStore.read($0) }
    report.expect(
        before.slotViews[127].kind == .none && applied.view.slotViews[127].voice == parent
            && applied.view.dirty && unchanged == diskBefore && staged?.children[0] == child,
        cppID: id + "undefined-slot", message: "undefined kit materializes dirty in memory with exact raw children")
    let sibling = VgVoice(macro: .square2, key: 70)
    _ = try store.applyVoicegroupEdit(
        input: .init(id: before.id, operation: .set(.init(slot: 127, value: sibling, expected: parent))))
    let undo = KitEditInput(
        id: before.id, slot: 127, parent: nil, subgroupSymbol: "", children: [], table: nil,
        materialization: materialization)
    guard case .applied(let reverted) = try store.applyKitEdit(input: undo, expected: .authoritative) else {
        report.fail(id + "undefined-slot", "authoritative undo did not restore undefined")
        return
    }
    let restored = try store.kitSnapshot(id: before.id, slot: 127)
    let restoredSlots = (0..<128).allSatisfy { (slot: Int) -> Bool in
        reverted.view.slotViews[slot].kind == before.slotViews[slot].kind
            && reverted.view.slotViews[slot].voice == before.slotViews[slot].voice
    }
    report.expect(
        restoredSlots && restored?.parent == nil && restored?.voicegroup == "_fixture_rich",
        cppID: id + "undefined-slot", message: "kit undo removes the complete insertion despite a later scalar edit")
    _ = try store.applyKitEdit(input: edit, expected: .parent(nil))
    guard let saved = try store.saveVoicegroup(id: before.id) else {
        report.fail(id + "undefined-slot", "materialized kit save was superseded")
        return
    }
    let reopened = try openRichSource(at: root)
    let savedParentBytes = try ProjectFileStore.read(parentPath)
    report.expect(
        !saved.dirty && reopened.voiceAt(slot: 127) == parent
            && savedParentBytes != diskBefore[0],
        cppID: id + "undefined-slot", message: "normal song save writes the re-materialized parent line")
    let sample = try store.sampleAsset(symbol: "DirectSoundWaveData_fixture_loop")
    let inputs = try store.bankBuildInputs()
    let resolved = try BankBuilder(inputs: inputs).resolveSample(
        symbol: Array("DirectSoundWaveData_fixture_loop".utf8)[...])
    if let wave = resolved {
        let header = Span(_unsafeStart: wave, count: 1)[0]
        if let data = header.data {
            let pcm = Span(_unsafeStart: data, count: Int(header.size))
            report.expect(
                sample?.pcm == (0..<pcm.count).map { (index: Int) -> Int8 in pcm[index] }
                    && sample?.frequency == header.freq && sample?.looped == (header.status & 0x4000 != 0)
                    && sample?.loopStart == Int(header.loopStart),
                cppID: id + "sampleAsset-bin", message: "bin sample copy preserves cached PCM and playback metadata")
        } else {
            report.fail(id + "sampleAsset-bin", "fixture bin sample has no PCM")
        }
    } else {
        report.fail(id + "sampleAsset-bin", "fixture bin sample did not resolve")
    }
    let missingSample = try store.sampleAsset(symbol: "missing_kit_sample")
    report.expect(
        missingSample == nil, cppID: id + "sampleAsset-missing", message: "an unknown project sample is a soft miss")
}
