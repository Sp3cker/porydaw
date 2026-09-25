import Foundation
import PorydawProject

// Only exact savecore.cpp stimulus/oracle ports enter the row inventory.
// A051/A076 preserve their bank-byte oracles but not the MainWindow song save/undo stimulus.
internal let saveCoreRowIDs: [String] = ["A079"]

internal func runSaveCoreSuite(_ report: CheckReport) {
    saveCoreBankRoundTrip(report)
    saveCoreSourceSaveAndPreview(report)
    saveCoreSectionRefusals(report)
}

private func saveCoreBankRoundTrip(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("porydaw-savecore-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("sound/voicegroups/savecheck.inc")
    let original = Data("voice_group savecheck\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n".utf8)
    do {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try original.write(to: path)
        let store = try VoicegroupStore(projectRoot: root.path)
        let initial = try store.loadBank(voicegroupArg: "_savecheck")
        report.expect(!initial.dirty, cppID: "savecore/A079",
                      message: "A079: initially selected bank is clean")
        guard let voice = initial.slotViews.first?.voice else {
            report.fail("source-save/S1", "S1: square-voice fixture failed to load")
            return
        }
        var changed = voice
        changed.release = 2
        let firstEdit = try store.applyVoicegroupEdit(input: .init(
            id: initial.id, operation: .set(.init(slot: 0, value: changed, expected: voice))))
        guard case .applied(let edited) = firstEdit else {
            report.fail("source-save/S2", "S2: expected release edit to apply")
            return
        }
        report.expect(edited.view.dirty && edited.view.slotViews[0].voice?.release == 2,
                      cppID: "source-save/S2", message: "S2: edited release dirties the bank")
        let saved = try store.saveVoicegroup(id: initial.id)
        report.expect(saved?.dirty == false, cppID: "source-save/S3",
                      message: "S3: saving publishes a clean bank")
        report.expectEqual(expected: true, actual: try Data(contentsOf: path) != original,
                           cppID: "savecore/A051",
                           what: "A051: partial — bank-only save changes its on-disk voicegroup bytes")

        // The C++ test undoes the voice edit and saves again; use the public bank
        // operation rather than synthesizing a QWidget undo shortcut.
        let secondEdit = try store.applyVoicegroupEdit(input: .init(
            id: initial.id, operation: .set(.init(slot: 0, value: voice, expected: changed))))
        guard case .applied = secondEdit else {
            report.fail("source-save/S4", "S4: reversing the voice edit failed")
            return
        }
        _ = try store.saveVoicegroup(id: initial.id)
        report.expectEqual(expected: original, actual: try Data(contentsOf: path),
                           cppID: "savecore/A076",
                           what: "A076: partial — bank-only reversal and save restore the original voicegroup bytes")
    } catch {
        report.fail("source-save/S1", "S1: bank fixture, edit, or save failed: \(error)")
    }
}

private func saveCoreSourceSaveAndPreview(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("porydaw-source-save-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sound = root.appendingPathComponent("sound", isDirectory: true)
    let singlePath = sound.appendingPathComponent("voicegroups/solo.inc")
    let multiPath = sound.appendingPathComponent("voice_groups.inc")
    let original = Data("@ untouched\r\nvoice_group solo\r\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\r\n".utf8)
    let multi = Data("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n"
        .appending("\t.align 2\nvoicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 3\n").utf8)
    do {
        try FileManager.default.createDirectory(at: singlePath.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try original.write(to: singlePath)
        let source = VoicegroupSource()
        var error: String?
        guard source.open(projectRoot: root.path, voicegroupArg: "_solo", error: &error),
              var voice = source.voiceAt(slot: 0) else {
            report.fail("source-save/S5", "S5: could not open single-file fixture: \(error ?? "unknown")")
            return
        }
        report.expectEqual(expected: Array(original), actual: source.renderPreview(), cppID: "source-save/S5",
                           what: "S5: per-file preview retains the entire original buffer")
        report.expectEqual(expected: "solo", actual: source.previewShadowName, cppID: "source-save/S18",
                           what: "S18: per-file shadow basename uses the source file, not the declaration")
        voice.release = 2
        report.expect(source.setVoice(slot: 0, voice: voice) && source.dirty,
                      cppID: "source-save/S6", message: "S6: editing one voice marks its source dirty")
        let pending = source.sourceBytes()
        report.expectEqual(expected: Array(original), actual: Array(try Data(contentsOf: singlePath)), cppID: "source-save/S7",
                           what: "S7: unsaved edit leaves disk bytes unchanged")
        voice.release = 3
        report.expect(source.setVoice(slot: 0, voice: voice) && !source.didSave(savedBytes: pending),
                      cppID: "source-save/S8",
                      message: "S8: an older saved snapshot cannot clean a newer edit")
        report.expect(source.dirty, cppID: "source-save/S9",
                      message: "S9: rejected stale save retains the dirty state")
        let savedCleanly = (try? source.save()) == true
        report.expect(savedCleanly && !source.dirty, cppID: "source-save/S10",
                      message: "S10: source save adopts current bytes as the pristine baseline")
        let saved = try Data(contentsOf: singlePath)
        let beforeLines = ProjectFileStore.splitLines(original).lines
        let afterLines = ProjectFileStore.splitLines(saved).lines
        report.expectEqual(expected: beforeLines.count, actual: afterLines.count, cppID: "source-save/S11",
                           what: "S11: save retains line count")
        if beforeLines.count == afterLines.count {
            report.expectEqual(expected: Array(beforeLines.dropLast()), actual: Array(afterLines.dropLast()),
                               cppID: "source-save/S12",
                               what: "S12: only the edited voice line differs; comments and header retain CRLF")
            report.expectEqual(expected: Optional(Data("\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 3\r".utf8)),
                               actual: afterLines.last, cppID: "source-save/S13",
                               what: "S13: edited line keeps its CRLF and argument formatting")
        }
        report.expectEqual(expected: Array(saved), actual: source.renderPreview(), cppID: "source-save/S14",
                           what: "S14: per-file preview renders saved bytes in full")

        try multi.write(to: multiPath)
        let section = VoicegroupSource()
        guard section.open(projectRoot: root.path, voicegroupArg: "_first", error: &error) else {
            report.fail("source-save/S15", "S15: could not open monolithic fixture: \(error ?? "unknown")")
            return
        }
        report.expect(section.isMonolithic && section.previewShadowName == "voicegroup_first",
                      cppID: "source-save/S15",
                      message: "S15: monolithic preview uses the selected declaration basename")
        report.expectEqual(expected: Array("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n".utf8),
                           actual: section.renderPreview(), cppID: "source-save/S16",
                           what: "S16: monolithic preview isolates the first section and excludes its sibling")
        report.expectEqual(expected: multi, actual: try Data(contentsOf: multiPath), cppID: "source-save/S17",
                           what: "S17: preview never persists its section to the project file")
    } catch {
        report.fail("source-save/S1", "S1: source fixture or save failed: \(error)")
    }
}

private func saveCoreRefused(_ source: VoicegroupSource) -> Bool {
    do {
        _ = try source.save()
        return false
    } catch {
        return true
    }
}

private func saveCoreSectionRefusals(_ report: CheckReport) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("porydaw-section-refusal-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("sound/voice_groups.inc")
    let second = "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 3\n"
    let original = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n\t.align 2\n" + second).utf8)
    let overlapping = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 7\n\t.align 2\n" + second).utf8)
    let malformed = Data(("voicegroup_first:\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n\t.align 2\n" + second).utf8)
    let sibling = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 1\n\t.align 2\n" +
                        "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 9\n").utf8)
    let expected = Data(("voicegroup_first::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 2\n\t.align 2\n" +
                         "voicegroup_second::\n\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 9\n").utf8)
    do {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try original.write(to: path)
        let source = VoicegroupSource()
        var error: String?
        guard source.open(projectRoot: root.path, voicegroupArg: "_first", error: &error),
              var voice = source.voiceAt(slot: 0) else {
            report.fail("source-save/S19", "S19: could not open section fixture: \(error ?? "unknown")")
            return
        }
        voice.release = 2
        guard source.setVoice(slot: 0, voice: voice) else {
            report.fail("source-save/S19", "S19: section edit did not apply")
            return
        }
        let pending = source.sourceBytes()
        func keepsPending() -> Bool {
            source.dirty && source.voiceAt(slot: 0) == voice && source.sourceBytes() == pending
        }

        try overlapping.write(to: path)
        let overlapRefused = saveCoreRefused(source)
        let overlapDisk = try Data(contentsOf: path)
        report.expect(overlapRefused && overlapDisk == overlapping && keepsPending(),
                      cppID: "source-save/S19",
                      message: "S19: an overlapping disk edit refuses save and keeps disk and pending bytes")
        try malformed.write(to: path)
        let malformedRefused = saveCoreRefused(source)
        let malformedDisk = try Data(contentsOf: path)
        report.expect(malformedRefused && malformedDisk == malformed && keepsPending(),
                      cppID: "source-save/S20",
                      message: "S20: a malformed selected label refuses save and keeps disk and pending bytes")
        try FileManager.default.removeItem(at: path)
        report.expect(saveCoreRefused(source) && !FileManager.default.fileExists(atPath: path.path) &&
                      keepsPending(), cppID: "source-save/S21",
                      message: "S21: a missing source refuses save without recreating it")
        try sibling.write(to: path)
        let saved = (try? source.save()) == true
        let savedDisk = try Data(contentsOf: path)
        report.expect(saved && savedDisk == expected && !source.dirty && source.sourceBytes() == Array(expected),
                      cppID: "source-save/S22",
                      message: "S22: save writes only the selected section into the sibling-changed image")
    } catch {
        report.fail("source-save/S19", "S19: section refusal fixture failed: \(error)")
    }
}
