import Foundation
import PorydawCore
import PorydawCoreCheckNative

@testable import PorydawApp

@MainActor
internal func sessionCatalogOutageRetainsLastValid(report: CheckReport, fixtureRoot: String) {
    let id = "vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-catalog-outage")
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    func until(_ predicate: () -> Bool, seconds: TimeInterval = 25) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }
    app.openProjectAndSong(path: root, label: "mus_session_test")
    guard
        until({
            (app.songOpen && !app.settingsVoicegroupArgs().isEmpty)
                || !app.lastSaveError.isEmpty
        }), app.songOpen,
        !app.settingsVoicegroupArgs().isEmpty, let session = app.selectedDocument
    else {
        report.fail(id, "catalog outage fixture failed to open its staged song")
        return
    }
    let before = app.settingsVoicegroupArgs()
    let revision = app.voiceList.catalogRevision
    let argument = session.document.state.config.voicegroupArgument
    let loadName = session.bankLoadName
    let sourcePath = session.bankLease.sourcePath
    let voiceLoadName = app.voiceList.bankLoadName
    let service = ProjectService()
    do {
        try runBlocking { try await service.open(root: root) }
    } catch {
        report.fail(id, "catalog outage fixture failed to open its second project service: \(error)")
        return
    }
    let sound = URL(fileURLWithPath: root).appendingPathComponent("sound")
    let hidden = URL(fileURLWithPath: root).appendingPathComponent("sound.catalog-outage")
    var isHidden = false
    defer {
        if isHidden {
            do {
                try FileManager.default.moveItem(at: hidden, to: sound)
            } catch {
                report.fail(id, "catalog outage cleanup could not restore sound: \(error)")
            }
        }
    }
    guard !FileManager.default.fileExists(atPath: hidden.path) else {
        report.fail(id, "catalog outage scratch destination already exists")
        return
    }
    do {
        try FileManager.default.moveItem(at: sound, to: hidden)
        isHidden = true
    } catch {
        report.fail(id, "catalog outage scratch sound directory could not be hidden: \(error)")
        return
    }
    report.expect(
        FileManager.default.fileExists(atPath: hidden.path), cppID: id,
        message: "catalog outage hides the staged sound directory")
    do {
        _ = try runBlocking { try await service.voicegroupCatalog() }
        report.fail(id, "catalog outage scan unexpectedly succeeded")
    } catch ProjectServiceError.operationFailed(let message) {
        report.expectEqual(
            expected: "Project sound directory is unavailable.", actual: message,
            cppID: id, what: "the project service refuses the catalog scan with the fork outage message")
    } catch {
        report.fail(id, "catalog outage scan threw an unexpected error: \(error)")
    }
    let failed: Bool
    do {
        failed = try runBlocking { await app.refreshVoicegroupCatalog() }
    } catch {
        report.fail(id, "catalog outage refresh could not settle: \(error)")
        return
    }
    report.expect(
        !failed && app.lastSaveError.isEmpty, cppID: id,
        message: "catalog outage refresh fails without a save error")
    report.expect(
        app.settingsVoicegroupArgs() == before && app.voiceList.catalogRevision == revision,
        cppID: id, message: "catalog outage keeps the last valid voicegroup choices")
    report.expect(
        session.document.state.config.voicegroupArgument == argument
            && session.bankLoadName == loadName && session.bankLease.sourcePath == sourcePath
            && app.voiceList.bankLoadName == voiceLoadName, cppID: id,
        message: "catalog outage keeps the song voicegroup binding")
    report.expect(
        !app.voiceList.isLoading, cppID: id,
        message: "catalog outage leaves the voicegroup browser settled")
    do {
        try FileManager.default.moveItem(at: hidden, to: sound)
        isHidden = false
    } catch {
        report.fail(id, "catalog recovery could not restore the staged sound directory: \(error)")
        return
    }
    report.expect(
        FileManager.default.fileExists(atPath: sound.path), cppID: id,
        message: "catalog recovery restores the staged sound directory")
    let recovered: Bool
    do {
        recovered = try runBlocking { await app.refreshVoicegroupCatalog() }
    } catch {
        report.fail(id, "catalog recovery refresh could not settle: \(error)")
        return
    }
    report.expect(
        recovered && app.voiceList.catalogRevision == revision + 1, cppID: id,
        message: "catalog refresh settles after sound recovery")
    report.expect(
        app.settingsVoicegroupArgs() == before, cppID: id,
        message: "recovered catalog republishes the same voicegroup choices")
    report.expect(
        !app.voiceList.isLoading, cppID: id,
        message: "recovered catalog leaves the voicegroup browser settled")
}
