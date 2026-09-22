import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
private func velocityPriorityRows(_ report: CheckReport, _ rows: [(String, Bool)]) {
    for (row, predicate) in rows {
        report.expect(predicate, cppID: "velocity/velocityhitpriority.cpp", message: row)
    }
}

@MainActor
private func priorityTimelineVelocity(_ fixture: drawerVelocityLegacyFixture,
                                      _ id: NoteID) -> Int? {
    fixture.session.timeline.events.first { $0.noteID == id && $0.data1 > 0 }.map { Int($0.data1) }
}

@MainActor
private func priorityFixture(_ session: DocumentSession, _ service: ProjectService,
                             loudVelocity: Int = 70)
    -> (drawerVelocityLegacyFixture, NoteID)?
{
    let fixture = drawerVelocityLegacyFixture(session: session, service: service,
                                              includeOverlap: true,
                                              loudVelocity: loudVelocity)
    guard fixture.notes.count == 4,
          let overlap = fixture.notes.first(where: { $0.tick == 20 }) else { return nil }
    return (fixture, overlap.id)
}

@MainActor
func drawerVelocityHitPriorityGapPredicates(_ report: CheckReport,
                                            session: DocumentSession,
                                            service: ProjectService) {
    guard let (selected, selectedOverlap) = priorityFixture(session, service) else {
        report.fail("velocity/velocityhitpriority.cpp", "selected-circle fixture admission failed")
        return
    }
    let selectedNotes = [selected.notes[0], selected.notes[1], selected.notes[3]]
    guard let selectedHandle = selected.page.publishedHandlesSnapshot.first(where: {
        $0.noteID == selectedOverlap
    }) else {
        report.fail("velocity/velocityhitpriority.cpp", "selected overlap handle missing")
        return
    }
    selected.session.setSelectedNotes([selectedOverlap])
    selected.page.refreshFromDocument()
    let selectedBefore = drawerVelocityDocumentSnapshot(selected.document)
    velocityPriorityRows(report, [
        ("A001", selected.document.note(selectedOverlap) != nil),
        ("A002", priorityTimelineVelocity(selected, selectedOverlap) == 20),
        ("A003", selected.session.selectedNoteOrder == [selectedOverlap]),
    ])
    _ = selected.page.pointerPress(x: selectedHandle.x, y: selectedHandle.y, surface: 1,
                                   button: 1, modifiers: 0)
    velocityPriorityRows(report, [
        ("A005", selected.page.observation.targetNoteID == selectedOverlap
            && selected.session.selectedNoteOrder == [selectedOverlap]),
    ])
    _ = selected.page.pointerRelease(x: selectedHandle.x, y: selectedHandle.y, button: 1)
    velocityPriorityRows(report, [
        ("A006", selected.document.revision == selectedBefore.revision),
        ("A007", selected.document.history.currentIdentity == selectedBefore.identity),
        ("A008", selected.document.note(selectedOverlap)?.velocity == 20),
        ("A009", selected.document.note(selectedNotes[0].id)?.velocity == 20),
        ("A010", selected.document.note(selectedNotes[1].id)?.velocity == 70),
        ("A011", selected.document.note(selectedNotes[2].id)?.velocity == 70),
        ("A012", selected.session.selectedNoteOrder == [selectedOverlap]),
    ])

    guard let (unselected, unselectedOverlap) = priorityFixture(session, service) else {
        report.fail("velocity/velocityhitpriority.cpp", "unselected-circle fixture admission failed")
        return
    }
    let unselectedNotes = [unselected.notes[0], unselected.notes[1], unselected.notes[3]]
    guard let unselectedHandle = unselected.page.publishedHandlesSnapshot.first(where: {
        $0.noteID == unselectedOverlap
    }) else {
        report.fail("velocity/velocityhitpriority.cpp", "unselected overlap handle missing")
        return
    }
    unselected.session.setSelectedNotes([unselectedNotes[0].id])
    unselected.page.refreshFromDocument()
    let unselectedBefore = drawerVelocityDocumentSnapshot(unselected.document)
    velocityPriorityRows(report, [
        ("A013", unselected.document.note(unselectedOverlap) != nil),
        ("A014", priorityTimelineVelocity(unselected, unselectedOverlap) == 20),
        ("A015", unselected.session.selectedNoteOrder == [unselectedNotes[0].id]),
    ])
    _ = unselected.page.pointerPress(x: unselectedHandle.x, y: unselectedHandle.y, surface: 1,
                                     button: 1, modifiers: 0)
    velocityPriorityRows(report, [
        ("A017", unselected.page.observation.targetNoteID == unselectedOverlap
            && unselected.session.selectedNoteOrder == [unselectedOverlap]),
    ])
    _ = unselected.page.pointerRelease(x: unselectedHandle.x, y: unselectedHandle.y, button: 1)
    velocityPriorityRows(report, [
        ("A018", unselected.document.revision == unselectedBefore.revision),
        ("A019", unselected.document.history.currentIdentity == unselectedBefore.identity),
        ("A020", unselected.document.note(unselectedOverlap)?.velocity == 20),
        ("A021", unselected.document.note(unselectedNotes[0].id)?.velocity == 20),
        ("A022", unselected.document.note(unselectedNotes[1].id)?.velocity == 70),
        ("A023", unselected.document.note(unselectedNotes[2].id)?.velocity == 70),
        ("A024", unselected.session.selectedNoteOrder == [unselectedOverlap]),
    ])

    guard let (stem, stemOverlap) = priorityFixture(session, service, loudVelocity: 20) else {
        report.fail("velocity/velocityhitpriority.cpp", "selected-stem fixture admission failed")
        return
    }
    let stemNotes = [stem.notes[0], stem.notes[1], stem.notes[3]]
    stem.session.setSelectedNotes([stemNotes[0].id])
    stem.page.refreshFromDocument()
    let stemBefore = drawerVelocityDocumentSnapshot(stem.document)
    let stemX = stem.session.camera.displayX(tick: 16, origin: 0, dpr: stem.page.devicePixelRatio)
    let stemY = stem.page.axisModel.velocityToY(20)
    velocityPriorityRows(report, [
        ("A025", stem.document.note(stemOverlap) != nil),
        ("A026", priorityTimelineVelocity(stem, stemNotes[1].id) == 20),
        ("A027", priorityTimelineVelocity(stem, stemOverlap) == 20),
        ("A028", stem.session.selectedNoteOrder == [stemNotes[0].id]),
    ])
    _ = stem.page.pointerPress(x: stemX, y: stemY, surface: 1, button: 1, modifiers: 0)
    velocityPriorityRows(report, [
        ("A030", stem.page.observation.targetNoteID == stemNotes[0].id
            && stem.session.selectedNoteOrder == [stemNotes[0].id]),
    ])
    _ = stem.page.pointerRelease(x: stemX, y: stemY, button: 1)
    velocityPriorityRows(report, [
        ("A031", stem.document.revision == stemBefore.revision),
        ("A032", stem.document.history.currentIdentity == stemBefore.identity),
        ("A033", stem.document.note(stemOverlap)?.velocity == 20),
        ("A034", stem.document.note(stemNotes[0].id)?.velocity == 20),
        ("A035", stem.document.note(stemNotes[1].id)?.velocity == 20),
        ("A036", stem.document.note(stemNotes[2].id)?.velocity == 70),
        ("A037", stem.session.selectedNoteOrder == [stemNotes[0].id]),
    ])

    let moved = drawerVelocityLegacyFixture(session: session, service: service)
    guard moved.notes.count == 3, let laterHandle = moved.handle(moved.notes[2]) else {
        report.fail("velocity/velocityhitpriority.cpp", "moved-node fixture admission failed")
        return
    }
    let movedNotes = moved.notes
    let movedBefore = drawerVelocityDocumentSnapshot(moved.document)
    let movedX = moved.session.camera.displayX(tick: 12, origin: 0,
                                                dpr: moved.page.devicePixelRatio)
    velocityPriorityRows(report, [("A038", moved.session.selectedNotes.isEmpty)])
    _ = moved.page.pointerPress(x: laterHandle.x, y: laterHandle.y, surface: 1,
                                button: 1, modifiers: 0)
    velocityPriorityRows(report, [
        ("A040", moved.page.observation.targetNoteID == movedNotes[2].id
            && moved.session.selectedNoteOrder == [movedNotes[2].id]),
    ])
    _ = moved.page.pointerMove(x: movedX, y: laterHandle.y, buttons: 1)
    velocityPriorityRows(report, [
        ("A041", moved.page.frozenPreview[movedNotes[2].id] != nil),
        ("A042", moved.page.frozenPreview[movedNotes[2].id] != nil),
        ("A043", moved.page.frozenPreview[movedNotes[2].id] == 70),
    ])
    _ = moved.page.pointerRelease(x: movedX, y: laterHandle.y, button: 1)
    velocityPriorityRows(report, [
        ("A044", moved.page.frozenPreview[movedNotes[2].id] == nil),
        ("A045", moved.document.revision == movedBefore.revision),
        ("A046", moved.document.history.currentIdentity == movedBefore.identity),
        ("A047", moved.document.note(movedNotes[0].id)?.velocity == 20),
        ("A048", moved.document.note(movedNotes[1].id)?.velocity == 70),
        ("A049", moved.document.note(movedNotes[2].id)?.velocity == 70),
        ("A050", priorityTimelineVelocity(moved, movedNotes[0].id) == 20),
        ("A051", priorityTimelineVelocity(moved, movedNotes[1].id) == 70),
        ("A052", priorityTimelineVelocity(moved, movedNotes[2].id) == 70),
        ("A053", moved.session.selectedNoteOrder == [movedNotes[2].id]),
    ])

    let right = drawerVelocityLegacyFixture(session: session, service: service)
    guard right.notes.count == 3, let quietHandle = right.handle(right.notes[0]) else {
        report.fail("velocity/velocityhitpriority.cpp", "right-press fixture admission failed")
        return
    }
    let rightNotes = right.notes
    right.session.setSelectedNotes([rightNotes[0].id, rightNotes[2].id])
    right.page.refreshFromDocument()
    let rightBefore = drawerVelocityDocumentSnapshot(right.document)
    velocityPriorityRows(report, [
        ("A054", right.session.selectedNoteOrder == [rightNotes[0].id, rightNotes[2].id]),
    ])
    _ = right.page.pointerPress(x: quietHandle.x, y: quietHandle.y, surface: 1,
                                button: 2, modifiers: 0)
    velocityPriorityRows(report, [
        ("A056", right.session.selectedNoteOrder == [rightNotes[0].id, rightNotes[2].id]),
    ])
    _ = right.page.pointerRelease(x: quietHandle.x, y: quietHandle.y, button: 2)
    velocityPriorityRows(report, [
        ("A057", right.document.revision == rightBefore.revision),
        ("A058", right.document.history.currentIdentity == rightBefore.identity),
        ("A059", right.document.note(rightNotes[0].id)?.velocity == 20),
        ("A060", right.document.note(rightNotes[1].id)?.velocity == 70),
        ("A061", right.document.note(rightNotes[2].id)?.velocity == 70),
        ("A062", priorityTimelineVelocity(right, rightNotes[0].id) == 20),
        ("A063", priorityTimelineVelocity(right, rightNotes[1].id) == 70),
        ("A064", priorityTimelineVelocity(right, rightNotes[2].id) == 70),
        ("A065", right.session.selectedNoteOrder == [rightNotes[0].id, rightNotes[2].id]),
    ])
}
