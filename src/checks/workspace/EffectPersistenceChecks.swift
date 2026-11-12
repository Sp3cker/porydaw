import Foundation
import PorydawBackups
import PorydawCore
import PorydawVoicegroup

@testable import PorydawApp
@testable import PorydawDocument

private struct EffectsJSONProbe: Decodable {
    struct Effect: Decodable {
        let classUID: String
        let component: String?
        let controller: String?
    }
    let version: Int
    let effects: [Effect]
}

@MainActor
private func effectNoticeCheck(
    _ report: CheckReport, root: String, label: String, expected: String
) throws {
    let shell = ShellPresenter()
    let app = shell.session
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    let service = ProjectService()
    try runBlocking { try await service.open(root: root) }
    app.catalogService = service
    app.projectRoot = root
    var observed = ""
    var noticeCount = 0
    let presentNotice = app.onOpenNoticeChanged
    app.onOpenNoticeChanged = {
        observed = app.lastOpenNotice
        noticeCount += 1
        presentNotice?()
    }
    defer { app.onOpenNoticeChanged = presentNotice }
    try runBlocking { await app.openTab(label: label, at: nil) }
    report.expect(
        app.songOpen && observed == expected && noticeCount == 1 && app.lastOpenNotice.isEmpty,
        cppID: "swiftcore/EffectPersistence::openNotices",
        message: "opening a real tab publishes the exact notice and the shell consumes it once: \(expected)")
}

@MainActor
private func effectCorruptChecks(
    _ report: CheckReport, service: ProjectService, root: String,
    label: String, path: String, valid: EffectsSidecar
) throws {
    let id = "swiftcore/EffectPersistence::corruptRecovery"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let corruptBytes = Data("not JSON".utf8)
    var moved: [String] = []
    for _ in 0..<2 {
        try ProjectFileStore.writeAtomic(path, data: corruptBytes)
        let result = try runBlocking {
            try await service.loadEffectsSidecar(label: label, trackCount: 16, now: fixedDate)
        }
        guard case .corrupt(let destination) = result else {
            report.fail(id, "corrupt JSON did not move aside")
            return
        }
        moved.append(destination)
    }
    report.expect(
        moved[0].range(of: #"\.corrupt-[0-9]{8}-[0-9]{6}\.json$"#, options: .regularExpression) != nil
            && moved[1] == String(moved[0].dropLast(5)) + "-1.json"
            && !ProjectFileStore.exists(path),
        cppID: id, message: "same-second corrupt renames use the timestamp then the smallest free -1 suffix")
    let firstBytes = try ProjectFileStore.read(moved[0])
    let secondBytes = try ProjectFileStore.read(moved[1])
    report.expect(
        firstBytes == corruptBytes && secondBytes == corruptBytes,
        cppID: id, message: "a collision preserves both original corrupt byte streams without overwrite")
    for destination in moved { try ProjectFileStore.remove(destination) }

    guard let first = valid.effects.first?.effect else {
        report.fail(id, "duplicate-identity fixture needs a saved effect")
        return
    }
    var aliased = first
    aliased.config.track = first.config.track + 1
    let sharedIdentity = EffectsSidecar(effects: [first, aliased])
    let sharedBytes = try sharedIdentity.encoded()
    try ProjectFileStore.writeAtomic(path, data: sharedBytes)
    let sharedResult = try runBlocking {
        try await service.loadEffectsSidecar(
            label: label, trackCount: aliased.config.track + 1, now: fixedDate)
    }
    guard case .corrupt(let sharedDestination) = sharedResult else {
        report.fail(id, "same-ID effects on different retained tracks were not classified as corrupt")
        return
    }
    let preservedSharedBytes = try ProjectFileStore.read(sharedDestination)
    report.expect(
        !ProjectFileStore.exists(path) && preservedSharedBytes == sharedBytes,
        cppID: id, message: "same-ID effects on different valid tracks move aside without losing original bytes")
    try ProjectFileStore.remove(sharedDestination)
    try ProjectFileStore.writeAtomic(path, data: sharedBytes)
    let missingResult = try runBlocking {
        try await service.loadEffectsSidecar(label: label, trackCount: aliased.config.track, now: fixedDate)
    }
    guard case .restored(let retained, let dropped) = missingResult else {
        report.fail(id, "an ID repeated only on a missing track incorrectly caused corrupt recovery")
        return
    }
    report.expect(
        dropped == 1 && retained.effects.map({ (stored: StoredEffect) in stored.effect }) == [first],
        cppID: id, message: "missing-track filtering runs before retained-effect identity validation")

    var wrongVersion = valid
    wrongVersion.version = 1
    let rejected = [try wrongVersion.encoded(), corruptBytes]
    for bytes in rejected {
        try ProjectFileStore.writeAtomic(path, data: bytes)
        let loaded = try runBlocking { try await service.openSong(label: label) }
        guard case .corrupt(let destination) = loaded.effects else {
            report.fail(id, "unsupported version or malformed JSON was not classified as corrupt on open")
            return
        }
        let file = try MidiFile.decode(loaded.midiBytes)
        let opened = DocumentSession.open(loaded: loaded, file: file, service: service, sampleRate: 48_000)
        report.expect(
            opened.document.effects.isEmpty
                && opened.lastOpenNotice == "\(label): the MIDI-effects sidecar was corrupt and was moved aside.",
            cppID: id, message: "ordinary open reports the exact corrupt-sidecar recovery notice")
        try runBlocking { _ = await opened.close() }
        try ProjectFileStore.remove(destination)
    }
    try ProjectFileStore.writeAtomic(path, data: corruptBytes)
    try effectNoticeCheck(
        report, root: root, label: label,
        expected: "\(label): the MIDI-effects sidecar was corrupt and was moved aside.")
}

@MainActor
private func effectDroppedChecks(
    _ report: CheckReport, service: ProjectService, root: String,
    label: String, path: String, effect: TrackEffect, trackCount: Int
) throws {
    let id = "swiftcore/EffectPersistence::droppedRecovery"
    let missing = TrackEffect(
        id: EffectID(raw: effect.id.raw + 10),
        config: TrackEffectConfig(track: trackCount, plugin: effect.config.plugin),
        pluginState: effect.pluginState)
    let duplicate = effect
    let negative = TrackEffect(
        id: EffectID(raw: effect.id.raw + 12),
        config: TrackEffectConfig(track: -1, plugin: effect.config.plugin))
    let sidecar = EffectsSidecar(effects: [effect, missing, duplicate, negative])
    let bytes = try sidecar.encoded()
    try ProjectFileStore.writeAtomic(path, data: bytes)
    let opened = try runBlocking { try await DocumentSession.open(service: service, label: label) }
    let expectedNotice = "\(label): 3 MIDI effect(s) referred to missing tracks and were removed."
    report.expect(
        opened.document.effects == [effect] && opened.lastOpenNotice == expectedNotice
            && opened.document.isDirty && opened.document.history.undoCount == 0,
        cppID: id, message: "missing, negative and duplicate tracks are dropped without manufacturing history")
    var changedConfig = effect.config
    changedConfig.plugin.name += " edited"
    try opened.document.updateEffect(effect.id, config: changedConfig, group: nil)
    try runBlocking { _ = try await opened.undo() }
    report.expect(
        opened.document.effects == [effect] && opened.document.isDirty,
        cppID: id, message: "undo after recovery cannot silently mark the repaired document clean")
    try runBlocking { try await opened.save() }
    let repaired = try JSONDecoder().decode(EffectsSidecar.self, from: ProjectFileStore.read(path))
    report.expect(
        !opened.document.isDirty && repaired.effects.map({ (stored: StoredEffect) in stored.effect }) == [effect],
        cppID: id,
        message: "saving a recovered document establishes the clean baseline and writes only surviving effects")
    try runBlocking { _ = await opened.close() }
    try ProjectFileStore.writeAtomic(path, data: bytes)
    try effectNoticeCheck(report, root: root, label: label, expected: expectedNotice)
    try ProjectFileStore.writeAtomic(path, data: EffectsSidecar(effects: [missing]).encoded())
    let empty = try runBlocking { try await DocumentSession.open(service: service, label: label) }
    report.expect(
        empty.document.effects.isEmpty && empty.document.isDirty
            && empty.lastOpenNotice == "\(label): 1 MIDI effect(s) referred to missing tracks and were removed.",
        cppID: id, message: "dropping the final effect still opens dirty with the exact singular-count notice")
    try runBlocking { try await empty.save() }
    report.expect(
        !empty.document.isDirty && !ProjectFileStore.exists(path),
        cppID: id, message: "saving an all-dropped sidecar removes it and clears recovery dirt")
    try runBlocking { _ = await empty.close() }
}

/// Exercises effect persistence through document editing and the real project service.
@MainActor
public func runEffectPersistenceChecks(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let id = "swiftcore/EffectPersistence::roundTrip"
    let label = "mus_effect_persistence"
    let forkLabel = "mus_effect_persistence_fork"
    do {
        let root = try runBlocking { await service.projectRoot }
        let directory = root + "/.porydaw/midi-effects"
        let path = directory + "/\(label).json"
        try ProjectFileStore.mkpath(directory)
        try ProjectFileStore.writeAtomic(path, data: Data("stale".utf8))
        let sourceSnapshot = try session.document.captureSave()
        let bareSnapshot = SaveSnapshot(
            bytes: sourceSnapshot.bytes, config: sourceSnapshot.config,
            flagsNeeded: sourceSnapshot.flagsNeeded, destination: sourceSnapshot.destination,
            revision: sourceSnapshot.revision, identity: sourceSnapshot.identity)
        try runBlocking { try await service.forkSongAs(label: label, snapshot: bareSnapshot) }
        let bareLoaded = try runBlocking { try await service.openSong(label: label) }
        report.expect(
            bareLoaded.effects == nil && !ProjectFileStore.exists(path)
                && bareLoaded.midiBytes == sourceSnapshot.bytes,
            cppID: id, message: "forking a bare snapshot removes a stale sidecar and preserves MIDI bytes")
        let live = try runBlocking { try await DocumentSession.open(service: service, label: label) }
        defer {
            do { try runBlocking { _ = await live.close() } } catch {
                report.fail(id, "could not close persistence session: \(error)")
            }
        }
        let document = live.document
        guard document.engineTracks.usedTrackCount > 0 else {
            report.fail(id, "persistence fixture needs an engine track")
            return
        }
        let originalBytes = try ProjectFileStore.read(live.document.source.midiPath)
        let timeline = live.timeline
        live.selectedTrack = 0
        live.selectedNoteOrder = document.notes(in: 0).prefix(1).map { (note: Note) in note.id }
        live.selectedNotes = Set(live.selectedNoteOrder)
        let selection = live.selectedNoteOrder
        var changes: [SessionChangeDomains] = []
        var playbackCount = 0
        var repairs = 0
        var selectionTransitions = 0
        live.onChange = { (change: SessionChange) in changes.append(change.domains) }
        live.onPlayback = { (_: PlaybackTimeline) in playbackCount += 1 }
        live.onViewportRepair = { (_: ViewportRepair) in repairs += 1 }
        let token = live.addSelectionTransitionObserver { (_: SelectionTransition) in selectionTransitions += 1 }
        defer { live.removeSelectionTransitionObserver(token) }
        let config = TrackEffectConfig(
            track: 0,
            plugin: PluginEffectConfig(
                modulePath: "/fixture/MidiEffect.vst3", classUID: Array(0..<16), name: "Fixture MIDI effect",
                input: .trackNotes, pacing: .realtime, prerollBars: 2))
        let effectID = try document.addEffect(config, replacing: nil)
        try runBlocking { try await live.save() }
        let cleanCount = document.history.undoCount
        changes.removeAll()
        let state = PluginStateBlob(component: [0, 255, 1, 128], controller: [5, 0, 254])
        try document.recordPluginState(effectID, state: state)
        report.expect(
            document.isDirty && document.history.undoCount == cleanCount + 1
                && changes == [[.effects, .dirty, .history]],
            cppID: "swiftcore/EffectPersistence::pluginStateHistory",
            message: "recorded settings create exactly one dirty undo step with effects-only domains")
        report.expect(
            playbackCount == 0 && repairs == 0 && selectionTransitions == 0
                && live.selectedNoteOrder == selection && live.selectedTrack == 0
                && live.timeline.events == timeline.events && live.timeline.tracks == timeline.tracks,
            cppID: "swiftcore/EffectPersistence::effectsOnlyPublication",
            message: "effects-only mutations leave timeline, playback and selection entirely untouched")
        try document.recordPluginState(effectID, state: state)
        report.expect(
            document.history.undoCount == cleanCount + 1 && changes.count == 1,
            cppID: "swiftcore/EffectPersistence::pluginStateHistory", message: "unchanged plugin state is a no-op")
        try runBlocking { _ = try await live.undo() }
        report.expect(
            !document.isDirty && document.effects[0].pluginState == nil,
            cppID: "swiftcore/EffectPersistence::pluginStateHistory",
            message: "one undo restores the saved state and clears dirt")
        try runBlocking { _ = try await live.redo() }
        report.expect(
            playbackCount == 0 && repairs == 0 && selectionTransitions == 0
                && changes == Array(repeating: [.effects, .dirty, .history], count: 3)
                && live.selectedNoteOrder == selection,
            cppID: "swiftcore/EffectPersistence::effectsOnlyPublication",
            message: "effect undo and redo also avoid timeline rebuild and selection reconciliation")
        try runBlocking { try await live.save() }
        let savedBytes = try ProjectFileStore.read(document.source.midiPath)
        report.expect(
            !document.isDirty && savedBytes == originalBytes && ProjectFileStore.exists(path),
            cppID: id, message: "saving plugin state clears dirt, creates JSON, and leaves MIDI byte-identical")
        let expectedEffects = document.effects
        let snapshot = try document.captureSave()
        guard let sidecar = snapshot.effectsSidecar else {
            report.fail(id, "save capture omitted effects")
            return
        }
        try runBlocking { try await service.backup(snapshot) }
        let backupRoot = try runBlocking { try await service.backups.directory() }
        let backupBucket = backupRoot.appendingPathComponent(label, isDirectory: true)
        let backupFiles = try FileManager.default.contentsOfDirectory(
            at: backupBucket, includingPropertiesForKeys: nil)
        let backupBytes = try backupFiles.map { (url: URL) in try ProjectFileStore.read(url.path) }
        report.expect(
            !backupFiles.isEmpty && backupFiles.allSatisfy({ (url: URL) in url.pathExtension == "mid" })
                && backupBytes.allSatisfy({ (bytes: Data) in bytes == originalBytes }),
            cppID: "swiftcore/EffectPersistence::backupsMidiOnly",
            message: "effects-bearing backups contain only the unchanged song MIDI, never plugin configuration or state"
        )
        let encoded = try sidecar.encoded()
        let decoded = try JSONDecoder().decode(EffectsJSONProbe.self, from: encoded)
        let stored = decoded.effects.first
        let secondEncoding = try sidecar.encoded()
        let diskSidecar = try ProjectFileStore.read(path)
        report.expect(
            encoded == secondEncoding && encoded == diskSidecar && decoded.version == 2
                && String(decoding: encoded, as: UTF8.self).hasPrefix("{\"effects\":[{\"classUID\":")
                && stored?.classUID == "000102030405060708090a0b0c0d0e0f"
                && stored?.component == Data(state.component).base64EncodedString()
                && stored?.controller == Data(state.controller).base64EncodedString(),
            cppID: "swiftcore/EffectPersistence::codec",
            message: "version-2 JSON is deterministic, sorted-key, lowercase UID and base64 state")
        let text = String(decoding: encoded, as: UTF8.self)
        let invalidUID = text.replacingOccurrences(
            of: "000102030405060708090a0b0c0d0e0f", with: "000102030405060708090A0B0C0D0E0F")
        let invalidState = text.replacingOccurrences(
            of: Data(state.component).base64EncodedString(), with: "not base64!")
        for invalid in [invalidUID, invalidState] {
            do {
                _ = try JSONDecoder().decode(EffectsSidecar.self, from: Data(invalid.utf8))
                report.fail("swiftcore/EffectPersistence::codec", "invalid UID or base64 was accepted")
            } catch is DecodingError {
                report.pass("swiftcore/EffectPersistence::codec", row: "invalid UID or base64 is rejected")
            }
        }
        let reopened = try runBlocking { try await DocumentSession.open(service: service, label: label) }
        report.expect(
            reopened.document.effects == expectedEffects && !reopened.document.isDirty
                && reopened.lastOpenNotice.isEmpty && reopened.timeline.events == timeline.events
                && reopened.timeline.tracks == timeline.tracks,
            cppID: id, message: "reopen restores every config, identity and state byte without changing the timeline")
        let next = try reopened.document.addEffect(config, replacing: effectID)
        report.expect(next.raw > effectID.raw, cppID: id, message: "restored maximum identity is never reused")
        try runBlocking { _ = await reopened.close() }
        try runBlocking { try await service.forkSongAs(label: forkLabel, snapshot: snapshot) }
        let forkPath = directory + "/\(forkLabel).json"
        let forkBytes = try ProjectFileStore.read(forkPath)
        report.expect(
            forkBytes == encoded,
            cppID: "swiftcore/EffectPersistence::forkAndDelete",
            message: "fork writes the same sidecar under the new label")
        try runBlocking { try await service.deleteSong(label: forkLabel) }
        report.expect(
            !ProjectFileStore.exists(forkPath), cppID: "swiftcore/EffectPersistence::forkAndDelete",
            message: "song deletion removes its effects sidecar")
        try document.removeEffect(effectID)
        try runBlocking { try await live.save() }
        let removedBytes = try ProjectFileStore.read(document.source.midiPath)
        let removedSnapshot = try document.captureSave()
        report.expect(
            !ProjectFileStore.exists(path) && removedBytes == originalBytes
                && removedSnapshot.effectsSidecar == nil,
            cppID: id, message: "removing all effects deletes JSON and keeps bare MIDI byte-identical")
        let bare = try runBlocking { try await service.openSong(label: label) }
        report.expect(
            bare.effects == nil && bare.midiBytes == Array(originalBytes),
            cppID: id, message: "a song with no effects reopens exactly as before")
        try effectDroppedChecks(
            report, service: service, root: root, label: label, path: path,
            effect: expectedEffects[0], trackCount: document.engineTracks.usedTrackCount)
        try effectCorruptChecks(report, service: service, root: root, label: label, path: path, valid: sidecar)
        try ProjectFileStore.writeAtomic(path, data: encoded)
        try runBlocking { try await service.deleteSong(label: label) }
        report.expect(
            !ProjectFileStore.exists(path), cppID: "swiftcore/EffectPersistence::forkAndDelete",
            message: "deleting a song after recovery also removes its sidecar")
    } catch {
        report.fail(id, "effect persistence operation failed: \(error)")
    }
}
