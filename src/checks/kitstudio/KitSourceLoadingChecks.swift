import Foundation
import PorydawKitStudio
import PorydawSample

@testable import PorydawApp

@MainActor
func runKitSourceLoadingChecks(_ report: CheckReport) {
    let ordered = report.scoped(cppID: "swiftcore/KitStudioWorkflow::sourceLoadOrder")
    let closed = report.scoped(cppID: "swiftcore/KitStudioWorkflow::closedWindowSourceLoad")
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        ordered.expect(false, message: "source loading requires a staged fixture directory")
        return
    }
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-kit-source-loading")
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    app.openProject(path: root)
    do {
        try runBlocking {
            while !app.projectOpen && app.lastSaveError.isEmpty { await Task.yield() }
        }
    } catch {
        ordered.expect(false, message: "project open did not settle: \(error)")
        return
    }
    guard app.projectOpen, app.catalogService != nil else {
        ordered.expect(false, message: "source loading fixture failed to open: \(app.lastSaveError)")
        return
    }
    let directory = URL(fileURLWithPath: root, isDirectory: true)
    let first = directory.appendingPathComponent("first_source.wav")
    let second = directory.appendingPathComponent("second_source.wav")
    var sample = ProcessedSample()
    sample.s8 = [Int8](repeating: 32, count: 512)
    sample.size = 512
    sample.freq = 13379 * 1024
    sample.declaredRate = 13379
    do {
        let wav = SampleWavWriter.bytes(for: sample)
        try wav.write(to: first)
        try wav.write(to: second)
    } catch {
        ordered.expect(false, message: "source fixture could not be written: \(error)")
        return
    }
    let studio = app.kitStudio()
    defer { studio.dispose() }
    studio.requestOpen()
    guard let editor = studio.presenter() else {
        ordered.expect(false, message: "Split Studio did not open")
        return
    }
    studio.loadSource(path: first.path)
    studio.dropLibrarySample(path: second.path, onKey: 48)
    ordered.expect(editor.session.sources.isEmpty, message: "source imports do not run synchronously")
    do {
        try runBlocking {
            let deadline = Date().addingTimeInterval(20)
            while editor.session.sources.count < 2 && Date() < deadline { await Task.yield() }
            if editor.session.sources.count < 2 { throw RunBlockingError.timeout }
        }
    } catch {
        ordered.expect(false, message: "ordered source imports did not settle: \(error)")
        return
    }
    ordered.expectEqual(
        expected: [first.path, second.path], actual: editor.session.sources.map(\.sample.sourcePath),
        what: "load and drop append in request order")
    let dropped = editor.session.sources[1].slices.first?.name
    ordered.expect(
        dropped != nil
            && editor.draft.drumkitZones.contains { (zone: KitZone) -> Bool in
                zone.sampleName == dropped && zone.startKey == 48
            }, message: "the dropped source is placed on its requested key")
    let droppedID = editor.sliceId(row: 1)
    ordered.expect(
        droppedID != 0 && editor.sliceName(id: droppedID) == dropped,
        message: "the dropped slice has a draft identity for selection and editing")

    studio.close()
    studio.windowReleased()
    studio.requestOpen()
    guard let closedEditor = studio.presenter() else {
        closed.expect(false, message: "Split Studio did not reopen")
        return
    }
    studio.loadSource(path: first.path)
    studio.close()
    studio.windowReleased()
    studio.requestOpen()
    guard let replacement = studio.presenter() else {
        closed.expect(false, message: "replacement Split Studio did not open")
        return
    }
    studio.loadSource(path: second.path)
    do {
        try runBlocking {
            let deadline = Date().addingTimeInterval(20)
            while replacement.session.sources.isEmpty && Date() < deadline { await Task.yield() }
            if replacement.session.sources.isEmpty { throw RunBlockingError.timeout }
        }
    } catch {
        closed.expect(false, message: "replacement source import did not settle: \(error)")
        return
    }
    closed.expect(
        closedEditor.session.sources.isEmpty, message: "a source finishing after close cannot modify its window")
    closed.expectEqual(
        expected: [second.path], actual: replacement.session.sources.map(\.sample.sourcePath),
        what: "a late source cannot enter the replacement window")

    let failed = report.scoped(cppID: "swiftcore/KitStudioWorkflow::sourceLoadError")
    let missing = directory.appendingPathComponent("missing.wav")
    let revision = studio.alertRevision
    studio.dropLibrarySample(path: missing.path, onKey: 50)
    do {
        try runBlocking {
            let deadline = Date().addingTimeInterval(20)
            while studio.alertRevision == revision && Date() < deadline { await Task.yield() }
            if studio.alertRevision == revision { throw RunBlockingError.timeout }
        }
    } catch {
        failed.expect(false, message: "source import failure did not settle: \(error)")
        return
    }
    failed.expectEqual(
        expected: String(describing: SampleImportFailure("cannot read \(missing.path).")),
        actual: studio.alertText, what: "source import retains the original error alert")
    failed.expectEqual(expected: 1, actual: replacement.session.sources.count, what: "failed drop adds no source")

    let emptyDrop = report.scoped(cppID: "swiftcore/KitStudioWorkflow::sourceDropIntoEmpty")
    studio.close()
    studio.windowReleased()
    studio.requestOpen()
    guard let emptyEditor = studio.presenter() else {
        emptyDrop.expect(false, message: "empty Split Studio did not open")
        return
    }
    studio.dropLibrarySample(path: first.path, onKey: 60)
    do {
        try runBlocking {
            let deadline = Date().addingTimeInterval(20)
            while emptyEditor.session.sources.isEmpty && Date() < deadline { await Task.yield() }
            if emptyEditor.session.sources.isEmpty { throw RunBlockingError.timeout }
        }
    } catch {
        emptyDrop.expect(false, message: "first dropped source did not settle: \(error)")
        return
    }
    let firstDropped = emptyEditor.session.sources[0].slices.first?.name
    emptyDrop.expect(
        firstDropped != nil
            && emptyEditor.draft.drumkitZones.contains { (zone: KitZone) -> Bool in
                zone.sampleName == firstDropped && zone.startKey == 60
            }, message: "the first dropped source is placed at the requested key")
    let firstID = emptyEditor.sliceId(row: 0)
    emptyDrop.expect(
        firstID != 0 && emptyEditor.sliceName(id: firstID) == firstDropped,
        message: "the first dropped slice has a draft identity")
}
