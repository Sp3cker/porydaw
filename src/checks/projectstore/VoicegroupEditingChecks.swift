import Foundation
import PorydawCore
import PorydawProject
import PorydawProjectNative

// A002 is a Qt session-pointer guard; A086–A092 depend on retired create/append APIs.
internal let voicegroupEditingRowIDs: [String] = [
    "A001", "A003", "A004", "A005", "A006", "A007", "A008", "A009", "A010", "A011", "A012",
    "A013", "A014", "A015", "A016", "A017", "A018", "A019", "A020", "A021", "A022", "A023",
    "A024", "A025", "A026", "A027", "A028", "A029", "A030", "A031", "A032", "A033", "A034",
    "A035", "A036", "A037", "A038", "A039", "A040", "A041", "A042", "A043", "A044", "A045",
    "A046", "A047", "A048", "A049", "A050", "A051", "A052", "A053", "A054", "A055", "A056",
    "A057", "A058", "A059", "A060", "A061", "A062", "A063", "A064", "A065", "A066", "A067",
    "A068", "A069", "A070", "A071", "A072", "A073", "A074", "A075", "A076", "A077", "A078",
    "A079", "A080", "A081", "A082", "A083", "A084", "A085", "A093", "A094", "A095",
    "A096", "A097", "A098",
]

internal func runVoicegroupEditingSuite(_ report: CheckReport) {
    editingBlankSlot(report)
    editingSparseInsertions(report)
    for family in 0..<7 {
        editingFamily(family, report)
    }
    editingDisplayNames(report)
}

private func editingExpect(_ row: String, _ result: Bool, _ report: CheckReport, _ message: String) {
    report.expect(result, cppID: "voicegroupsourceediting/\(row)", message: "\(row): \(message)")
}

private func editingEqual<T: Equatable>(_ row: String, _ expected: T, _ actual: T,
                                         _ report: CheckReport, _ message: String) {
    report.expectEqual(expected, actual, cppID: "voicegroupsourceediting/\(row)",
                       what: "\(row): \(message)")
}

private func editingRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "voicegroup-editing-\(UUID().uuidString)", isDirectory: true)
}

private func editingRichSource(root: URL) throws -> VoicegroupSource {
    guard let fixture = CheckEnvironment.fixtureRoot else {
        throw EditingFixtureError.open("staged decompproject fixture root is unavailable")
    }
    try FileManager.default.copyItem(at: URL(filePath: fixture), to: root)
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
    let root = editingRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        let source = try editingRichSource(root: root)
        let baseline = editingLoad(root: root, name: source.loadName)
        editingExpect("A001", baseline != nil, report, "fixture session opens source and native baseline")
        guard let baseline else { return }
        defer { voicegroup_free(baseline) }
        let slot = (0..<128).first { source.kindAt(slot: $0) == .none }
        editingExpect("A003", slot != nil, report, "fixture_rich retains a materializable blank slot")
        guard let slot else { return }
        let before = source.sourceBytes()
        let created = VgVoice(macro: .square1, sustain: 15)
        let draft = source.voiceDraft(slot: slot, blank: created)
        editingExpect("A004", draft != nil, report, "blank slot produces a draft")
        editingExpect("A005", draft?.materializesBlank == true, report, "draft marks materialization")
        editingEqual("A006", created, draft?.voice, report, "draft retains the requested voice")
        editingExpect("A007", source.setVoice(slot: slot, voice: created), report, "blank slot accepts voice")
        editingExpect("A008", source.voiceAt(slot: slot) != nil, report, "inserted voice is present")
        editingEqual("A009", created, source.voiceAt(slot: slot), report, "inserted voice equals request")
        editingExpect("A010", source.dirty, report, "materialization marks source dirty")
        editingExpect("A011", source.restoreSourceBytes(before), report, "original source bytes restore")
        editingEqual("A012", VgLineKind.none, source.kindAt(slot: slot), report, "restored slot is empty")
        editingEqual("A013", before, source.sourceBytes(), report, "restored bytes equal original")
        editingExpect("A014", !source.dirty, report, "restoring pristine bytes clears dirty")
    } catch {
        report.expect(false, cppID: "voicegroupsourceediting/A001", message: "A001: fixture setup failed: \(error)")
    }
}

private func editingSparseInsertions(_ report: CheckReport) {
    let root = editingRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("sound/voicegroups", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        editingExpect("A015", FileManager.default.fileExists(atPath: root.path), report,
                      "temporary directory is available")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        editingExpect("A016", FileManager.default.fileExists(atPath: folder.path), report,
                      "sound/voicegroups directory exists")
        let path = folder.appendingPathComponent("sparse.inc")
        try Data("voice_group sparse, 36\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0\n".utf8).write(to: path)
        editingExpect("A017", FileManager.default.fileExists(atPath: path.path), report,
                      "sparse source fixture is written")
        let source = VoicegroupSource()
        var error: String?
        let opened = source.open(projectRoot: root.path, voicegroupArg: "_sparse", error: &error)
        editingExpect("A018", opened, report, "sparse source opens: \(error ?? "")")
        guard opened, let original = source.voiceAt(slot: 36) else { return }
        let beforeFirst = VgVoice(macro: .square2, sustain: 15)
        let afterLast = VgVoice(macro: .noise, sustain: 15, release: 3)
        editingEqual("A019", VgLineKind.none, source.kindAt(slot: 12), report, "slot 12 starts blank")
        editingEqual("A020", VgLineKind.none, source.kindAt(slot: 80), report, "slot 80 starts blank")
        editingExpect("A021", source.setVoice(slot: 12, voice: beforeFirst), report, "insert before first voice")
        editingExpect("A022", source.voiceAt(slot: 12) != nil, report, "slot 12 is populated")
        editingEqual("A023", beforeFirst, source.voiceAt(slot: 12), report, "slot 12 matches inserted voice")
        editingExpect("A024", source.voiceAt(slot: 36) != nil, report, "original slot is populated")
        editingEqual("A025", original, source.voiceAt(slot: 36), report, "original slot is unchanged")
        editingExpect("A026", source.setVoice(slot: 80, voice: afterLast), report, "insert after last voice")
        editingExpect("A027", source.voiceAt(slot: 80) != nil, report, "slot 80 is populated")
        editingEqual("A028", afterLast, source.voiceAt(slot: 80), report, "slot 80 matches inserted voice")
        editingExpect("A029", try source.save(), report, "sparse source saves")
        editingExpect("A030", !source.dirty, report, "save clears dirty")
        let reloaded = VoicegroupSource()
        let reopened = reloaded.open(projectRoot: root.path, voicegroupArg: "_sparse", error: &error)
        editingExpect("A031", reopened, report, "saved sparse source reopens: \(error ?? "")")
        guard reopened else { return }
        editingExpect("A032", reloaded.voiceAt(slot: 12) != nil, report, "slot 12 survives reload")
        editingEqual("A033", beforeFirst, reloaded.voiceAt(slot: 12), report, "slot 12 survives exactly")
        editingExpect("A034", reloaded.voiceAt(slot: 36) != nil, report, "slot 36 survives reload")
        editingEqual("A035", original, reloaded.voiceAt(slot: 36), report, "slot 36 survives exactly")
        editingExpect("A036", reloaded.voiceAt(slot: 80) != nil, report, "slot 80 survives reload")
        editingEqual("A037", afterLast, reloaded.voiceAt(slot: 80), report, "slot 80 survives exactly")
        let loaded = editingLoad(root: root, name: "sparse")
        editingExpect("A038", loaded != nil, report, "native loader accepts saved sparse source")
        guard let loaded else { return }
        defer { voicegroup_free(loaded) }
        editingEqual("A039", vgMacroVoiceType(.square2), editingTone(loaded, 12).type, report,
                     "inserted slot 12 loads as square 2")
        editingEqual("A040", vgMacroVoiceType(.square1), editingTone(loaded, 36).type, report,
                     "original slot 36 loads as square 1")
        editingEqual("A041", vgMacroVoiceType(.noise), editingTone(loaded, 80).type, report,
                     "inserted slot 80 loads as noise")
    } catch {
        report.expect(false, cppID: "voicegroupsourceediting/A015", message: "A015: sparse fixture failed: \(error)")
    }
}

private func editingLoad(root: URL, name: String, config: UnsafePointer<VoicegroupLoaderConfig>? = nil)
    -> UnsafeMutablePointer<LoadedVoiceGroup>? {
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
    let packed: UInt = (tone.type != UInt8(VOICE_KEYSPLIT) &&
        tone.type != UInt8(VOICE_KEYSPLIT_ALL) &&
        (cgb == UInt8(VOICE_SQUARE_1) || cgb == UInt8(VOICE_SQUARE_2) || cgb == UInt8(VOICE_NOISE)))
        ? UInt(bitPattern: tone.wavePointer) : 0
    return EditingSnapshot(type: tone.type, key: tone.key, panSweep: tone.panSweep,
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
              let table = aggregate.keySplitTable else { return nil }
        tone = subgroup[Int(table[key])]
    } else {
        tone = aggregate
    }
    return tone.type & (UInt8(VOICE_KEYSPLIT) | UInt8(VOICE_KEYSPLIT_ALL)) == 0 ? tone : nil
}

private func editingSameWave(_ left: UnsafeMutablePointer<WaveData>?,
                             _ right: UnsafeMutablePointer<WaveData>?) -> Bool {
    if left == right { return true }
    guard let left, let right else { return false }
    let a = left.pointee
    let b = right.pointee
    guard a.type == b.type, a.status == b.status, a.freq == b.freq,
          a.loopStart == b.loopStart, a.size == b.size else { return false }
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
          lhs.sustain == rhs.sustain, lhs.release == rhs.release else { return false }
    let family = lhs.type & UInt8(VOICE_TYPE_CGB_MASK)
    if family == UInt8(VOICE_SQUARE_1) || family == UInt8(VOICE_SQUARE_2) ||
        family == UInt8(VOICE_NOISE) {
        return lhs.wavePointer == rhs.wavePointer
    }
    if family == UInt8(VOICE_PROGRAMMABLE_WAVE) {
        guard let left = lhs.wavePointer, let right = rhs.wavePointer else {
            return lhs.wavePointer == rhs.wavePointer
        }
        return UnsafeBufferPointer(start: UnsafeRawPointer(left).assumingMemoryBound(to: UInt8.self), count: 16)
            .elementsEqual(UnsafeBufferPointer(
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
        return actual.key == expected.key && actual.pan == expected.pan &&
            actual.symbol == expected.symbol && actual.sweep == expected.sweep &&
            actual.duty == expected.duty && actual.period == expected.period &&
            actual.attack == expected.attack && actual.decay == expected.decay &&
            actual.sustain == expected.sustain && actual.release == expected.release
    }
}

private func editingChangedLineCount(_ before: Data, _ after: Data) -> Int {
    let old = before.split(separator: 10, omittingEmptySubsequences: false)
    let new = after.split(separator: 10, omittingEmptySubsequences: false)
    guard old.count == new.count else { return -1 }
    return zip(old, new).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
}

private func editingFamily(_ family: Int, _ report: CheckReport) {
    let root = editingRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        let source = try editingRichSource(root: root)
        let file = URL(filePath: source.filePath)
        let before = try Data(contentsOf: file)
        let baseline = editingLoad(root: root, name: source.loadName)
        editingExpect("A042", baseline != nil, report, "fixture session opens source and native baseline")
        guard let baseline else { return }
        defer { voicegroup_free(baseline) }
        let drumkits = VoicegroupSource.drumkitInstruments(root.path)
        if family >= 5 {
            editingExpect("A049", drumkits.count >= 2, report, "fixture retains two drumkit definitions")
            guard drumkits.count >= 2 else { return }
        }
        var slot: Int
        var edited: VgVoice
        switch family {
        case 0:
            let found = editingFirstSlot(source) {
                $0 == .directSound || $0 == .directSoundNoResample || $0 == .directSoundAlt
            }
            editingExpect("A043", found != nil, report, "fixture retains a DirectSound voice")
            guard let found, var voice = source.voiceAt(slot: found) else { return }
            slot = found
            voice.key = 61
            voice.attack = 200
            voice.decay = 100
            voice.sustain = 50
            voice.release = 25
            let donor = source.voiceAt(slot: 1)
            editingExpect("A044", donor != nil, report, "fixture retains donor at slot 1")
            guard let donor else { return }
            voice.symbol = donor.symbol
            edited = voice
        case 1:
            let found = editingFirstSlot(source) { $0 == .square1 || $0 == .square1Alt }
            editingExpect("A045", found != nil, report, "fixture retains a square-1 voice")
            guard let found, var voice = source.voiceAt(slot: found) else { return }
            slot = found
            voice.duty = 3
            voice.sustain = 15
            voice.sweep = 7
            edited = voice
        case 2:
            let found = editingFirstSlot(source) { $0 == .noise || $0 == .noiseAlt }
            editingExpect("A046", found != nil, report, "fixture retains a noise voice")
            guard let found, var voice = source.voiceAt(slot: found) else { return }
            slot = found
            voice.period = 1 - (voice.period & 1)
            edited = voice
        case 3:
            let found = editingFirstSlot(source) { $0 == .progWave || $0 == .progWaveAlt }
            editingExpect("A047", found != nil, report, "fixture retains a programmable-wave voice")
            guard let found, var voice = source.voiceAt(slot: found) else { return }
            slot = found
            voice.release = (voice.release & 7) == 5 ? 6 : 5
            edited = voice
        case 4:
            let found = editingFirstSlot(source) { $0 == .keysplit }
            let donor = found.flatMap { source.voiceAt(slot: $0 + 1) }
            editingExpect("A048", found != nil && donor?.macro == .keysplit, report,
                          "fixture retains adjacent keysplit voices")
            guard let found, let donor, var voice = source.voiceAt(slot: found) else { return }
            slot = found
            voice.symbol = donor.symbol
            voice.keysplitTable = donor.keysplitTable
            edited = voice
        case 5:
            let found = editingFirstSlot(source) { $0 == .keysplitAll }
            editingExpect("A050", found != nil, report, "fixture retains a drumkit aggregate")
            guard let found, var voice = source.voiceAt(slot: found) else { return }
            slot = found
            voice.symbol = drumkits[drumkits.count - 1]
            edited = voice
        default:
            slot = 4
            editingExpect("A051", source.voiceAt(slot: slot) != nil, report,
                          "conversion slot 4 is populated")
            edited = VgVoice(macro: .keysplitAll, symbol: drumkits[0])
        }
        var aggregateOracleSlot = family == 4 ? slot + 1 : -1
        if family >= 5 {
            aggregateOracleSlot = (0..<128).first { index in
                index != slot && source.voiceAt(slot: index)?.macro == .keysplitAll &&
                    source.voiceAt(slot: index)?.symbol == edited.symbol
            } ?? -1
            editingExpect("A052", aggregateOracleSlot >= 0, report,
                          "selected drumkit has an existing aggregate")
        }
        let expectedName = family == 0 ? editingVoiceName(baseline, 1) :
            (family == 4 ? editingVoiceName(baseline, slot + 1) :
                (family >= 5 ? editingLoaderVoiceName(edited.symbol) : editingVoiceName(baseline, slot)))
        editingExpect("A053", source.setVoice(slot: slot, voice: edited), report, "edited voice is accepted")
        editingExpect("A054", source.dirty, report, "edited voice makes source dirty")
        let previewDir = root.appendingPathComponent(".porydaw/vgpreview", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
        editingExpect("A055", FileManager.default.fileExists(atPath: previewDir.path), report,
                      "preview directory is available")
        let previewFile = previewDir.appendingPathComponent("\(source.loadName).inc")
        try Data(source.renderPreview()).write(to: previewFile)
        editingExpect("A056", FileManager.default.fileExists(atPath: previewFile.path), report,
                      "preview bytes are written to the loader path")
        var config = VoicegroupLoaderConfig()
        let previewPathBytes = Array(".porydaw/vgpreview".utf8) + [0]
        withUnsafeMutableBytes(of: &config.voicegroupPaths) { $0.copyBytes(from: previewPathBytes) }
        config.voicegroupPathCount = 1
        let preview = withUnsafePointer(to: &config) {
            editingLoad(root: root, name: source.loadName, config: $0)
        }
        editingExpect("A057", preview != nil, report, "native loader accepts edited preview")
        guard let preview else { return }
        defer { voicegroup_free(preview) }
        editingEqual("A058", expectedName, editingVoiceName(preview, slot), report,
                     "preview resolves edited display name")
        editingEqual("A059", vgMacroVoiceType(edited.macro), editingTone(preview, slot).type, report,
                     "preview loads the edited voice type")
        if family >= 4 {
            if aggregateOracleSlot >= 0 {
                editingExpect("A060", editingSameResolvedTone(
                    editingTone(preview, slot), editingTone(baseline, aggregateOracleSlot),
                    key: family >= 5 ? 36 : 60), report,
                    "preview aggregate resolves the same playable child as existing aggregate")
            } else {
                editingExpect("A060", false, report, "preview aggregate has no baseline oracle slot")
            }
        }
        editingExpect("A061", editingSameVoiceFields(source.voiceAt(slot: slot), edited), report,
                      "edited source retains the requested family fields")
        editingEqual("A062", before, try Data(contentsOf: file), report,
                     "preview does not modify the original file")
        editingExpect("A063", try source.save(), report, "edited source saves")
        editingExpect("A064", !source.dirty, report, "save clears dirty")
        editingEqual("A065", 1, editingChangedLineCount(before, try Data(contentsOf: file)), report,
                     "saving the edit changes exactly one source line")
        let reloaded = editingLoad(root: root, name: source.loadName)
        editingExpect("A066", reloaded != nil, report, "saved source loads as native bank")
        guard let reloaded else { return }
        defer { voicegroup_free(reloaded) }
        let tone = editingTone(reloaded, slot)
        editingEqual("A067", vgMacroVoiceType(edited.macro), tone.type, report,
                     "saved bank retains edited native voice type")
        if family >= 4 {
            editingExpect("A068", tone.subGroup != nil, report, "aggregate has a subgroup")
            if family == 4 {
                editingExpect("A069", tone.keySplitTable != nil, report, "keysplit retains lookup table")
            }
            if aggregateOracleSlot >= 0 {
                editingExpect("A070", editingSameResolvedTone(
                    tone, editingTone(baseline, aggregateOracleSlot),
                    key: family >= 5 ? 36 : 60), report,
                    "saved aggregate resolves unchanged child")
            } else {
                editingExpect("A070", false, report, "saved aggregate has no baseline oracle slot")
            }
        } else {
            editingEqual("A071", UInt8(truncatingIfNeeded: edited.key), tone.key, report, "native key")
            editingEqual("A072", UInt8(truncatingIfNeeded: edited.attack), tone.attack, report, "native attack")
            editingEqual("A073", UInt8(truncatingIfNeeded: edited.decay), tone.decay, report, "native decay")
            editingEqual("A074", UInt8(truncatingIfNeeded: edited.sustain), tone.sustain, report, "native sustain")
            editingEqual("A075", UInt8(truncatingIfNeeded: edited.release), tone.release, report, "native release")
            if family == 0 || family == 3 {
                editingEqual("A076", edited.pan == 0 ? UInt8(0) : UInt8(0x80 | edited.pan),
                             tone.panSweep, report, "native sample/wave pan flags")
            }
            if family == 1 {
                editingEqual("A077", UInt8(truncatingIfNeeded: edited.sweep), tone.panSweep,
                             report, "square sweep packing")
                editingEqual("A078", UInt(edited.duty & 0x03), UInt(bitPattern: tone.wavePointer),
                             report, "square duty packing")
            } else if family == 2 {
                editingEqual("A079", UInt(edited.period & 0x01), UInt(bitPattern: tone.wavePointer),
                             report, "noise period packing")
            }
        }
        editingEqual("A080", expectedName, editingVoiceName(reloaded, slot), report,
                     "saved bank resolves edited display name")
        for untouched in 0..<128 where untouched != slot {
            editingEqual("A081", editingSnapshot(baseline, untouched), editingSnapshot(reloaded, untouched),
                         report, "native slot \(untouched) remains equal to baseline")
        }
        let roundTrip = VoicegroupSource()
        var error: String?
        let opened = roundTrip.open(projectRoot: root.path, voicegroupArg: "_fixture_rich", error: &error)
        editingExpect("A082", opened, report, "saved edited source reopens: \(error ?? "")")
        guard opened else { return }
        editingExpect("A083", !roundTrip.dirty, report, "freshly opened source is pristine")
        editingExpect("A084", roundTrip.voiceAt(slot: slot) != nil, report,
                      "edited slot remains populated after reopen")
        editingExpect("A085", editingSameVoiceFields(roundTrip.voiceAt(slot: slot), edited), report,
                      "edited voice family fields survive save and reopen")
    } catch {
        report.expect(false, cppID: "voicegroupsourceediting/A042", message: "A042: family \(family) fixture failed: \(error)")
    }
}

private func editingDisplayNames(_ report: CheckReport) {
    editingEqual("A093", "Sample", vgMacroDisplayName(.directSound), report,
                 "DirectSound display name")
    editingEqual("A094", "Sample (fixed pitch)", vgMacroDisplayName(.directSoundNoResample), report,
                 "fixed-pitch sample display name")
    editingEqual("A095", "Sample (reverse)", vgMacroDisplayName(.directSoundAlt), report,
                 "reverse sample display name")
    editingEqual("A096", "Sample (fixed pitch)", m4aVoiceTypeName(UInt8(VOICE_DIRECTSOUND_NO_RESAMPLE)),
                 report, "native fixed-pitch sample type name")
    editingEqual("A097", "Sample (reverse)", m4aVoiceTypeName(UInt8(VOICE_DIRECTSOUND_ALT)),
                 report, "native reverse sample type name")
    editingEqual("A098", "Sample", m4aVoiceTypeName(UInt8(VOICE_KEYSPLIT)),
                 report, "native keysplit voice type name")
}
