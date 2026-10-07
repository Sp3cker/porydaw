import Foundation
import PorydawBackups
import PorydawCore
import PorydawDocument
import PorydawProject

private func midiBackupContents(in root: URL, label: String) throws -> [String: Data] {
    let folder = root.appendingPathComponent(label, isDirectory: true)
    guard FileManager.default.fileExists(atPath: folder.path) else { return [:] }
    let files = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    var contents: [String: Data] = [:]
    for file in files {
        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else { continue }
        contents[file.lastPathComponent] = try Data(contentsOf: file)
    }
    return contents
}

@MainActor
private func midiBackupLifecycleChecks(_ report: CheckReport, fixture: URL, root: URL) throws {
    let store = MidiBackupStore(root: root)
    let service = ProjectService(backups: store)
    let otherService = ProjectService(backups: store)
    let project = stageTestProject(in: fixture.path, projectName: "Projet été 雪")
    let otherProject = stageTestProject(in: fixture.path, projectName: "Autre projet 雪")
    try runBlocking {
        try await service.open(root: project)
        try await otherService.open(root: otherProject)
    }
    let first = try runBlocking { try await DocumentSession.open(service: service, label: "mus_session_test") }
    let second = try runBlocking { try await DocumentSession.open(service: otherService, label: "mus_session_test2") }
    defer {
        // Close retained timer tasks even when a fixture assertion throws.
        _ = try? runBlocking {
            _ = await first.close()
            _ = await second.close()
            await service.close()
            await otherService.close()
        }
    }
    let firstURL = URL(fileURLWithPath: first.document.source.midiPath)
    let secondURL = URL(fileURLWithPath: second.document.source.midiPath)
    let firstLabel = first.document.source.label
    let secondLabel = second.document.source.label
    let raw = try Data(contentsOf: firstURL)
    let otherRaw = try Data(contentsOf: secondURL)
    try runBlocking { try await first.backupNow() }
    let cleanContents = try midiBackupContents(in: root, label: firstLabel)
    report.expect(
        cleanContents.isEmpty,
        cppID: "midi-backups/clean-session", message: "a clean session creates no snapshot or fabricated baseline")
    _ = try first.document.addNotes([NewNote(track: 0, tick: 240, pitch: 74, duration: 24, velocity: 90)])
    _ = try second.document.addNotes([NewNote(track: 0, tick: 288, pitch: 79, duration: 24, velocity: 85)])
    let firstSnapshot = try first.document.captureSave()
    let secondSnapshot = try second.document.captureSave()
    let before = DocumentSnapshot(first.document)
    let undoCount = first.document.history.undoCount
    try runBlocking {
        try await first.backupNow()
        try await second.backupNow()
    }
    let firstContents = try midiBackupContents(in: root, label: firstLabel)
    let secondContents = try midiBackupContents(in: root, label: secondLabel)
    let firstBackup = firstContents["\(firstLabel)2.mid"]
    let secondBackup = secondContents["\(secondLabel)2.mid"]
    let decoded = try firstBackup.map { try MidiFile.decode(Array($0)) }
    var hasEditedNote = false
    if let decoded {
        editedNoteSearch: for chunk in decoded.chunks {
            for event in chunk.events {
                guard case .channel(let status, let key, _) = event.payload else { continue }
                let eventType: UInt8 = status & 0xF0
                if eventType == 0x90 && key == 74 && event.tick == 240 {
                    hasEditedNote = true
                    break editedNoteSearch
                }
            }
        }
    }
    let firstDiskAfterBackup = try Data(contentsOf: firstURL)
    let secondDiskAfterBackup = try Data(contentsOf: secondURL)
    report.expect(
        firstBackup == Data(firstSnapshot.bytes) && hasEditedNote
            && firstDiskAfterBackup == raw && first.document.isDirty
            && DocumentSnapshot(first.document) == before && first.document.history.undoCount == undoCount,
        cppID: "midi-backups/autosave-document",
        message: "backupNow decodes to edited notes without changing disk, revision, dirty state or history")
    report.expect(
        firstContents == ["\(firstLabel)1.mid": raw, "\(firstLabel)2.mid": Data(firstSnapshot.bytes)]
            && secondContents == ["\(secondLabel)1.mid": otherRaw, "\(secondLabel)2.mid": Data(secondSnapshot.bytes)]
            && secondBackup != firstBackup && secondDiskAfterBackup == otherRaw,
        cppID: "midi-backups/session-isolation",
        message: "distinct song labels in different projects retain their own original and edited bytes")
    try runBlocking { try await first.backupNow() }
    let afterUnchanged = try midiBackupContents(in: root, label: firstLabel)
    report.expect(
        afterUnchanged == firstContents,
        cppID: "midi-backups/unchanged-session",
        message: "a repeated backup of an unchanged dirty revision adds no record")
    try runBlocking { try await first.save() }
    let savedContents = try midiBackupContents(in: root, label: firstLabel)
    let firstDiskAfterSave = try Data(contentsOf: firstURL)
    report.expect(
        savedContents == [
            "\(firstLabel)1.mid": raw, "\(firstLabel)2.mid": Data(firstSnapshot.bytes), "\(firstLabel)3.mid": raw,
        ]
            && firstDiskAfterSave == Data(firstSnapshot.bytes) && !first.document.isDirty,
        cppID: "midi-backups/pre-save-raw",
        message: "a successful save retains exact prior disk bytes, distinct from the edited autosave")
    _ = try first.document.addNotes([NewNote(track: 0, tick: 336, pitch: 76, duration: 24, velocity: 89)])
    let pending = try first.document.captureSave()
    let dirtyBeforeFailure = DocumentSnapshot(first.document)
    let parked = root.appendingPathExtension("parked")
    try FileManager.default.moveItem(at: root, to: parked)
    defer {
        // Restore temporary filesystem obstruction after an early fixture failure.
        if FileManager.default.fileExists(atPath: parked.path) {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.moveItem(at: parked, to: root)
        }
    }
    try Data([1]).write(to: root)
    var backupFailed = false
    var saveFailed = false
    do { try runBlocking { try await first.backupNow() } } catch { backupFailed = true }
    do { try runBlocking { try await first.save() } } catch { saveFailed = true }
    let firstDiskAfterFailure = try Data(contentsOf: firstURL)
    report.expect(
        backupFailed && saveFailed && first.document.isDirty
            && DocumentSnapshot(first.document) == dirtyBeforeFailure
            && firstDiskAfterFailure == Data(firstSnapshot.bytes),
        cppID: "midi-backups/failure-gates-save",
        message: "backup failure prevents overwrite and preserves dirty document and history")
    try FileManager.default.removeItem(at: root)
    try FileManager.default.moveItem(at: parked, to: root)
    try runBlocking { try await first.backupNow() }
    let afterRetry = try midiBackupContents(in: root, label: firstLabel)
    report.expect(
        afterRetry["\(firstLabel)4.mid"] == Data(pending.bytes),
        cppID: "midi-backups/failed-revision-retry",
        message: "a failed autosave does not mark the unchanged revision backed up and can be retried")
    var external = Data(firstSnapshot.bytes)
    external.append(0x7F)
    try external.write(to: firstURL)
    let beforeConflict = try midiBackupContents(in: root, label: firstLabel)
    var conflict = false
    do { try runBlocking { try await first.save() } } catch is SaveConflictError { conflict = true }
    let firstDiskAfterConflict = try Data(contentsOf: firstURL)
    let afterConflict = try midiBackupContents(in: root, label: firstLabel)
    report.expect(
        conflict && first.document.isDirty && firstDiskAfterConflict == external
            && afterConflict == beforeConflict,
        cppID: "midi-backups/save-conflict",
        message: "an observed external MIDI conflict writes neither backups nor MIDI and remains dirty")
    try runBlocking { try await first.save(forceOverwrite: true) }
    let afterForcedSave = try midiBackupContents(in: root, label: firstLabel)
    let firstDiskAfterForcedSave = try Data(contentsOf: firstURL)
    report.expect(
        afterForcedSave["\(firstLabel)5.mid"] == external
            && firstDiskAfterForcedSave == Data(pending.bytes) && !first.document.isDirty,
        cppID: "midi-backups/forced-conflict-raw",
        message: "confirmed conflict overwrite preserves the exact external raw bytes before writing")
    let restarted = MidiBackupStore(root: root)
    try runBlocking {
        try await restarted.preserveOriginal(songName: first.document.source.label, bytes: pending.bytes)
    }
    let afterRestart = try midiBackupContents(in: root, label: firstLabel)
    report.expect(
        afterRestart == afterForcedSave && afterRestart["\(firstLabel)1.mid"] == raw,
        cppID: "midi-backups/repeated-save-baseline",
        message: "multiple real saves and store restart never replace the loaded raw baseline")
    _ = try second.document.addNotes([NewNote(track: 0, tick: 384, pitch: 81, duration: 24, velocity: 86)])
    let beforeClose = try midiBackupContents(in: root, label: secondLabel)
    let closed = try runBlocking { await second.close() }
    var refused = false
    do {
        try runBlocking { try await second.backupNow() }
    } catch {
        refused = true
    }
    report.expect(
        refused && second.isClosed, cppID: "midi-backups/closed-admission",
        message: "closed session refuses backup admission")
    let afterClose = try midiBackupContents(in: root, label: secondLabel)
    let secondDiskAfterClose = try Data(contentsOf: secondURL)
    report.expect(
        closed && second.isClosed && afterClose == beforeClose && secondDiskAfterClose == otherRaw,
        cppID: "midi-backups/closed-session",
        message: "a closed dirty session cannot create any new backup or overwrite its original")
}

@MainActor
public func runMidiBackupChecks(_ report: CheckReport) {
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(
        "midi-backups-\(UUID().uuidString)", isDirectory: true)
    // Removing the unique temporary fixture is best-effort cleanup.
    defer { try? FileManager.default.removeItem(at: fixture) }
    do {
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try midiBackupLifecycleChecks(
            report, fixture: fixture, root: fixture.appendingPathComponent("lifecycle", isDirectory: true))
    } catch {
        report.fail("midi-backups/lifecycle-fixture", "lifecycle regression failed: \(error)")
    }
}
