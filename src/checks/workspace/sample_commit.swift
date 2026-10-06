import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
import PorydawCore
@testable import PorydawDocument
import PorydawSample
import PorydawProject

@MainActor
internal func sampleCommitRefreshChecks(_ report: CheckReport, fixtureRoot: String) {
    let check = report.scoped(cppID: "swiftcore/ProjectService::sampleCommitRefresh")
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-sample-commit")
    let sound = root + "/sound"
    let inc = sound + "/direct_sound_data.inc"
    let name = "commit_tone"
    let symbol = "DirectSoundWaveData_" + name
    let service = ProjectService()
    do {
        try Data().write(to: URL(filePath: inc))
        try Data("include audio_rules.mk\n".utf8).write(to: URL(filePath: root + "/Makefile"))
        try Data("$(SOUND_BIN_DIR)/%.bin: sound/%.wav\n\t$(WAV2AGB) -b $< $@\n".utf8)
            .write(to: URL(filePath: root + "/audio_rules.mk"))
        try FileManager.default.createDirectory(
            atPath: sound + "/direct_sound_samples", withIntermediateDirectories: true)
        try runBlocking { try await service.open(root: root) }
        let first = try runBlocking { try await DocumentSession.open(service: service, label: "mus_session_test") }
        let peer = try runBlocking { try await DocumentSession.open(service: service, label: "mus_session_test2") }
        var rendered = ProcessedSample()
        rendered.s8 = (0..<64).map { Int8($0 - 32) }
        rendered.size = 64
        rendered.declaredRate = 22_050
        rendered.freq = 15_000_000
        let wav = SampleWavWriter.bytes(for: rendered)
        let request = SampleCommitRequest(name: name, wav: wav, update: false)
        try runBlocking { try await service.commitSample(request) }
        let persisted = try Data(contentsOf: URL(filePath: sound + "/direct_sound_samples/\(name).wav"))
        check.expect(persisted == wav, message: "sample WAV persists exact rendered bytes")
        let registration = try String(contentsOfFile: inc, encoding: .utf8)
        check.expect(registration.contains(symbol + "::"), message: "new symbol registers in assembly")
        let reopened = try runBlocking { try await service.readCommittedSample(name: name) }
        check.expect(reopened.wav == wav, message: "committed WAV can be reopened")
        let picked = try runBlocking { await service.pickerSound(symbol: symbol, kind: .sample) }
        if case .sample(let bytes, _, _, _, _, _) = picked {
            check.expect(bytes == rendered.s8, message: "picker reload resolves committed signed audio")
        } else {
            check.expect(false, message: "picker reload resolves committed signed audio")
        }
        guard let original = first.bankSlots[0].voice else {
            check.expect(false, message: "fixture provides editable destination slot")
            return
        }
        var assigned = original
        assigned.macro = BankVoiceMacro.directSound
        assigned.symbol = symbol
        _ = try runBlocking { try await first.applyBankEdit(slot: 0, value: assigned, expected: original) }
        check.expect(
            first.bankSlots[0].voice == assigned && peer.bankSlots[0].voice == assigned,
            message: "new sample assignment reaches both sessions")
        func slotZeroAudio(_ session: DocumentSession) -> [Int8]? {
            guard let wave = session.bankLease[0].wav, let data = wave.pointee.data else { return nil }
            return (0..<64).map { data[$0] }
        }
        let initialAudio = slotZeroAudio(first)
        let peerAudio = slotZeroAudio(peer)
        check.expect(
            initialAudio == rendered.s8 && peerAudio == rendered.s8,
            message: "new registered sample plays rendered bytes in both sessions")
        let historyCount = first.document.history.undoCount
        let peerHistoryCount = peer.document.history.undoCount
        guard var unsaved = peer.bankSlots[1].voice else {
            check.expect(false, message: "fixture provides adjacent editable slot")
            return
        }
        let previous = unsaved
        unsaved.release = unsaved.release == 255 ? 254 : unsaved.release + 1
        _ = try runBlocking { try await peer.applyBankEdit(slot: 1, value: unsaved, expected: previous) }
        let editCount = first.document.history.undoCount
        let peerEditCount = peer.document.history.undoCount
        let dirty = first.bankDirty
        let peerDirty = peer.bankDirty
        rendered.s8 = (0..<64).map { Int8(31 - $0) }
        let updatedWav = SampleWavWriter.bytes(for: rendered)
        let beforeInc = try Data(contentsOf: URL(filePath: inc))
        try runBlocking { try await service.commitSample(.init(name: name, wav: updatedWav, update: true)) }
        let afterInc = try Data(contentsOf: URL(filePath: inc))
        check.expect(afterInc == beforeInc, message: "sample update preserves registration bytes")
        check.expect(
            first.bankSlots[1].voice == unsaved && peer.bankSlots[1].voice == unsaved
                && first.bankDirty == dirty && peer.bankDirty == peerDirty,
            message: "rebind preserves unsaved edit and dirty state")
        check.expect(
            first.document.history.undoCount == editCount && peer.document.history.undoCount == peerEditCount,
            message: "sample update adds no bank history command")
        let refreshed = slotZeroAudio(first)
        let peerRefreshed = slotZeroAudio(peer)
        check.expect(
            refreshed == rendered.s8 && peerRefreshed == rendered.s8,
            message: "both live bank leases play updated bytes")
        let beforeRefusal = first.bankLease.publicationRevision
        let peerBeforeRefusal = peer.bankLease.publicationRevision
        do {
            _ = try runBlocking { try await service.commitSample(request) }
            check.expect(false, message: "duplicate name refuses as a typed registrar failure")
        } catch ProjectServiceError.operationFailed(let message) {
            check.expect(
                message.contains(name),
                message: "duplicate name refuses as a typed failure naming the sample")
        } catch {
            check.expect(false, message: "duplicate name refuses as a typed registrar failure")
        }
        check.expect(
            first.bankLease.publicationRevision == beforeRefusal
                && peer.bankLease.publicationRevision == peerBeforeRefusal
                && first.document.history.undoCount == editCount
                && peer.document.history.undoCount == peerEditCount,
            message: "refused duplicate publishes no bank edit")
        try runBlocking { _ = try await peer.undo() }
        try runBlocking { _ = try await first.undo() }
        check.expect(
            first.bankSlots[0].voice == original && peer.bankSlots[0].voice == original
                && first.document.history.undoCount >= historyCount
                && peer.document.history.undoCount >= peerHistoryCount,
            message: "undo assignment restores voices without undoing sample registration")
        check.expect(
            FileManager.default.fileExists(atPath: sound + "/direct_sound_samples/\(name).wav")
                && afterInc.contains(Data(symbol.utf8)),
            message: "undo assignment retains committed WAV and assembly symbol")
    } catch {
        check.expect(false, message: "sample commit lifecycle failed: \(error)")
    }
    check.expect(
        !FileManager.default.fileExists(atPath: root + "/.porydaw"),
        message: "sample commits create no .porydaw folder in the project")
    sampleProvenanceStoreChecks(report, projectRoot: root, name: name)
}

@MainActor
private func sampleProvenanceStoreChecks(_ report: CheckReport, projectRoot: String, name: String) {
    let check = report.scoped(cppID: "swiftcore/SampleProvenanceStore::appData")
    let store = SampleProvenanceStore(preferences: PreferencesStore())
    let otherRoot = projectRoot + "-other"
    var provenance = SampleProvenance()
    provenance.sourcePath = "/source/commit_tone.wav"
    provenance.sourceSha256 = "abc"
    provenance.leftOnly = true
    provenance.sf2Zone = 3
    provenance.params.loopStart = 77
    var other = provenance
    other.sourcePath = "/source/other_tone.wav"
    store.save(provenance, projectRoot: projectRoot, name: name)
    store.save(other, projectRoot: otherRoot, name: name)
    check.expect(
        SampleProvenanceStore(preferences: PreferencesStore())
            .load(projectRoot: projectRoot + "/", name: name) == provenance,
        message: "a fresh preference store reloads every provenance field for the project")
    check.expect(
        store.load(projectRoot: otherRoot, name: name) == other,
        message: "the same sample name in another project keeps its own provenance")
    store.remove(projectRoot: projectRoot, name: name)
    check.expect(
        store.load(projectRoot: projectRoot, name: name) == nil
            && store.load(projectRoot: otherRoot, name: name) == other,
        message: "removing provenance forgets only that project's sample")
    store.remove(projectRoot: otherRoot, name: name)
}
