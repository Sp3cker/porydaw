import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func pitchBendVertexPredicates(_ report: CheckReport, suite: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::vertexLifecycle"
    let service = ProjectService()
    let session = pitchBendSyntheticSession(suite, service: service)
    defer { withExtendedLifetime(service) {} }
    guard let scene = pitchBendCheckScene(report, cppID: id, session: session) else { return }
    let presenter = scene.presenter
    defer { presenter.cancelAndClose() }
    let graph = presenter.pitchGraph()
    let document = session.document
    let center = pitchBendCanvasPoint(graph, xFraction: 0.5, yFraction: 0.25)
    graph.press(x: center.x, y: center.y, modifiers: 0)
    graph.release(x: center.x, y: center.y, modifiers: 0)
    let point = graph.kernel.hitTest(x: center.x, y: center.y)
    guard let point, point.tick > Int(scene.note.tick), point.tick < Int(scene.noteEnd) else {
        report.fail(id, "the interior vertex fixture must be drawable")
        return
    }
    let tick = point.tick
    let initialBytes = coreTimeBytes(document)
    let initialIndex = document.history.undoIndex
    graph.press(
        x: graph.kernel.x(at: tick), y: graph.kernel.y(at: point.value),
        modifiers: 0x0800_0000)
    report.expect(
        graph.kernel.selectedTick == tick && graph.kernel.hasGesture,
        cppID: id, message: "an interior vertex hit selects its tick")
    let destination = pitchBendCanvasPoint(graph, xFraction: 0.75, yFraction: 0.75)
    graph.drag(x: destination.x, y: destination.y, modifiers: 0x0800_0000)
    graph.release(x: destination.x, y: destination.y, modifiers: 0x0800_0000)
    let moved = graph.kernel.selectedTick ?? -1
    report.expect(
        moved != tick && moved > Int(scene.note.tick)
            && moved < Int(scene.noteEnd) && graph.kernel.points[tick] == nil
            && document.history.undoIndex == initialIndex + 1,
        cppID: id,
        message: "an Alt drag moves the selected interior vertex in one entry")
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "undoing the Alt drag restores the moved vertex")
    presenter.documentDidChange()
    report.expect(
        coreTimeBytes(document) == initialBytes
            && graph.kernel.points[tick] == point.value,
        cppID: id, message: "undoing the Alt drag restores the moved vertex")
    graph.press(x: graph.kernel.x(at: tick), y: graph.kernel.y(at: point.value), modifiers: 0)
    graph.release(x: graph.kernel.x(at: tick), y: graph.kernel.y(at: point.value), modifiers: 0)
    let beforeDelete = document.history.undoIndex
    graph.removeSelectedVertex()
    report.expect(
        graph.kernel.points[tick] == nil
            && graph.kernel.points[graph.kernel.startTick] != nil
            && graph.kernel.points[graph.kernel.endTick] != nil
            && document.history.undoIndex == beforeDelete + 1,
        cppID: id,
        message: "deleting a selected interior vertex writes one entry and keeps both endpoints")
    let undoneDelete = document.history.undoDocument()
    presenter.documentDidChange()
    report.expect(
        undoneDelete && graph.kernel.points[tick] == point.value,
        cppID: id, message: "undoing the vertex delete restores the point")
    for endpoint in [graph.kernel.startTick, graph.kernel.endTick] {
        guard let value = graph.kernel.points[endpoint] else { continue }
        graph.press(
            x: graph.kernel.x(at: endpoint), y: graph.kernel.y(at: value),
            modifiers: 0)
        graph.release(
            x: graph.kernel.x(at: endpoint), y: graph.kernel.y(at: value),
            modifiers: 0)
        let before = coreTimeBytes(document)
        let index = document.history.undoIndex
        graph.removeSelectedVertex()
        report.expect(
            graph.kernel.selectedTick == endpoint
                && graph.kernel.points[endpoint] == value
                && coreTimeBytes(document) == before
                && document.history.undoIndex == index,
            cppID: id, message: "endpoint vertices select but never delete")
    }
    let start = pitchBendCanvasPoint(graph, xFraction: 0.25, yFraction: 0.75)
    let finish = pitchBendCanvasPoint(graph, xFraction: 0.8, yFraction: 0.25)
    let beforeSettle = document.history.undoIndex
    graph.press(x: start.x, y: start.y, modifiers: 0)
    graph.drag(x: finish.x, y: finish.y, modifiers: 0)
    report.expect(
        graph.kernel.hasGesture && document.history.undoIndex == beforeSettle,
        cppID: id, message: "a held graph gesture settles as a commit")
    presenter.settleAndClose()
    report.expect(
        !presenter.isOpen && !graph.kernel.hasGesture
            && document.history.undoIndex == beforeSettle + 1,
        cppID: id, message: "a held graph gesture settles as a commit")
    report.expect(
        !presenter.isOpen && coreTimeBytes(document) != initialBytes,
        cppID: id,
        message: "host-window loss settles and closes the editor without restoring roll focus")
}

@MainActor
func pitchBendOwnerLifetimePredicates(_ report: CheckReport, suite: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::duplicateNoteAtSameTickDoesNotReanchor"
    let service = ProjectService()
    var file = makeMidiFixture()
    file.chunks[1].events = [.channel(tick: 0, status: 0xC0, data0: 0)]
    let session = pitchBendSyntheticSession(suite, service: service, file: file)
    defer { withExtendedLifetime(service) {} }
    let document = session.document
    guard
        let ids = try? document.addNotes([
            NewNote(track: 0, tick: 240, pitch: 67, duration: 72, velocity: 91),
            NewNote(track: 0, tick: 240, pitch: 67, duration: 72, velocity: 73),
        ]), ids.count == 2,
        let original = document.note(ids[0]),
        let impostor = document.note(ids[1])
    else {
        report.fail(id, "the duplicate-note fixture must provide both distinct note identities")
        return
    }
    report.expect(
        document.notes(in: 0).count == 2, cppID: id,
        message: "the duplicate-note fixture holds exactly two notes")
    report.expect(
        impostor.id != original.id, cppID: id,
        message: "the duplicate note retains an independent identity")
    report.expect(
        impostor.tick == original.tick, cppID: id,
        message: "the impostor shares the anchor note's tick")
    report.expect(
        impostor.pitch == original.pitch, cppID: id,
        message: "the impostor shares the anchor note's key")
    report.expect(
        impostor.endTick == original.endTick, cppID: id,
        message: "the impostor shares the anchor note's editing span")
    let before = coreTimeBytes(document)
    let index = document.history.undoIndex
    guard let scene = pitchBendCheckScene(report, cppID: id, session: session) else { return }
    pitchBendObserveDocument(session, presenter: scene.presenter)
    report.expect(
        scene.note.id == original.id, cppID: id,
        message: "the editor opens on the original note rather than its impostor")
    report.expect(
        original.endTick == UInt64(scene.presenter.pitchGraph().kernel.endTick),
        cppID: id, message: "the open editor's graph spans exactly the selected note")
    document.deleteNotes([original.id])
    report.expect(
        !scene.presenter.isOpen, cppID: id,
        message: "deleting the anchored note closes the editor")
    report.expect(
        document.note(ids[1]) != nil, cppID: id,
        message: "the same-tick impostor survives deletion of the anchor")
    report.expect(
        document.note(original.id) == nil, cppID: id,
        message: "the anchored note's span is gone after deletion")
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "undo restores the anchored note and the exact prior song bytes")
    report.expectEqual(
        expected: index, actual: document.history.undoIndex, cppID: id,
        what: "undo restores the anchored note's history index")
    report.expectEqual(
        expected: before, actual: coreTimeBytes(document), cppID: id,
        what: "undo restores the anchored note and the exact prior song bytes")
    report.expect(
        pitchBendSpanAlive(session, note: original, noteEnd: scene.noteEnd),
        cppID: id, message: "undo restores the anchored note")
    report.expect(
        !scene.presenter.isOpen, cppID: id,
        message: "undo leaves the dismissed anchored editor closed")
    let moveID = "swiftcore/PitchBendEditingTest::externalMoveClosesAnchor"
    session.selectPrimaryTrack(0)
    session.setSelectedNotes([original.id])
    report.expect(
        scene.presenter.openSelected(), cppID: moveID,
        message: "the restored anchor note reopens for an external move")
    document.moveNotes([original.id], byTicks: 1, byKeys: 0)
    report.expect(
        !scene.presenter.isOpen, cppID: moveID,
        message: "moving the anchored note closes the editor")
    report.expect(
        document.note(ids[1]) != nil, cppID: moveID,
        message: "moving the anchor does not rebind the same-tick impostor")
}

@MainActor
func pitchBendExternalPreviewPredicates(_ report: CheckReport, suite: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::externalEditPreservesLivePreview"
    let service = ProjectService()
    let session = pitchBendSyntheticSession(suite, service: service)
    defer { withExtendedLifetime(service) {} }
    guard let scene = pitchBendCheckScene(report, cppID: id, session: session) else { return }
    let presenter = scene.presenter
    defer { presenter.cancelAndClose() }
    pitchBendObserveDocument(session, presenter: presenter)
    let graph = presenter.pitchGraph()
    let start = pitchBendCanvasPoint(graph, xFraction: 0.25, yFraction: 0.70)
    let finish = pitchBendCanvasPoint(graph, xFraction: 0.75, yFraction: 0.30)
    graph.press(x: start.x, y: start.y, modifiers: 0)
    graph.drag(x: finish.x, y: finish.y, modifiers: 0)
    let preview = graph.kernel.points
    let endValue = graph.kernel.endValue
    report.expect(
        graph.kernel.hasGesture, cppID: id,
        message: "an unfinished stroke keeps its live gesture")
    let document = session.document
    let before = coreTimeBytes(document)
    let index = document.history.undoIndex
    document.writeLane(
        track: 0, lane: .controller(0x15),
        from: scene.note.tick, through: scene.noteEnd,
        points: [
            LaneWrite(tick: scene.note.tick, value: 23),
            LaneWrite(tick: scene.noteEnd, value: 22),
        ])
    report.expectEqual(
        expected: index + 1, actual: document.history.undoIndex, cppID: id,
        what: "an external lane edit pushes exactly one history entry under the open gesture")
    report.expect(
        coreTimeBytes(document) != before, cppID: id,
        message: "the external lane edit changes the serialized song")
    report.expect(
        graph.kernel.points == preview && graph.kernel.endValue == endValue,
        cppID: id, message: "the live preview survives the external edit")
    report.expect(
        graph.kernel.hasGesture, cppID: id,
        message: "the gesture survives the external edit")
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "undoing the external edit restores the history entry")
    report.expectEqual(
        expected: index, actual: document.history.undoIndex, cppID: id,
        what: "undoing the external edit restores the history index")
    report.expectEqual(
        expected: before, actual: coreTimeBytes(document), cppID: id,
        what: "undoing the external edit restores the exact prior song bytes")
    report.expect(
        graph.kernel.points == preview && graph.kernel.endValue == endValue,
        cppID: id, message: "the live preview survives undo of the external edit")
    report.expect(
        graph.kernel.hasGesture, cppID: id,
        message: "the gesture survives undo of the external edit")
    report.expect(
        document.history.redoDocument(), cppID: id,
        message: "redo reapplies the external edit as one entry")
    report.expectEqual(
        expected: index + 1, actual: document.history.undoIndex, cppID: id,
        what: "redo reapplies the external edit at the next history index")
    report.expect(
        coreTimeBytes(document) != before, cppID: id,
        message: "redo reapplies the external lane edit to the serialized song")
    report.expect(
        graph.kernel.points == preview && graph.kernel.endValue == endValue,
        cppID: id, message: "the live preview survives redo of the external edit")
    report.expect(
        graph.kernel.hasGesture, cppID: id,
        message: "the gesture survives redo of the external edit")
    presenter.cancelAndClose()
    report.expect(
        !presenter.isOpen, cppID: id,
        message: "Escape closes the editor after the external-edit cycle")
}

@MainActor
func pitchBendUnterminatedPredicates(_ report: CheckReport, suite: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::unterminatedNoteRefusesEditing"
    var file = makeMidiFixture()
    file.chunks[1].events.append(.channel(tick: 168, status: 0x90, data0: 70, data1: 90))
    let service = ProjectService()
    let session = pitchBendSyntheticSession(suite, service: service, file: file)
    defer { withExtendedLifetime(service) {} }
    let document = session.document
    guard let note = document.notes(in: 0).first(where: { $0.tick == 168 && $0.pitch == 70 }) else {
        report.fail(id, "the unterminated note fixture is absent")
        return
    }
    report.expect(
        note.isUnterminated, cppID: id,
        message: "the fixture contains an unterminated note")
    report.expect(
        note.endTick == nil, cppID: id,
        message: "the unterminated note has no editable span endpoint")
    session.selectPrimaryTrack(0)
    session.setSelectedNotes([note.id])
    let grid = PianoGrid(session: session)
    let presenter = PitchBendPresenter(session: session, grid: grid, palette: grid.palette)
    pitchBendObserveDocument(session, presenter: presenter)
    let before = coreTimeBytes(document)
    report.expect(
        !presenter.openSelected(), cppID: id,
        message: "the G route refuses an unterminated note without opening the editor")
    report.expect(
        !presenter.isOpen, cppID: id,
        message: "an unterminated note leaves the editor closed")
    report.expectEqual(
        expected: before, actual: coreTimeBytes(document), cppID: id,
        what: "refusing the unterminated note leaves the song bytes unchanged")
}
