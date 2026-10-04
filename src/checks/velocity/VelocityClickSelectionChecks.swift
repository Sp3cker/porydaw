import Foundation
import PorydawApp
import PorydawCore

let drawerVelocityClickSelectionID = "swiftcore/VelocityClickSelection::clickSelection"
let drawerVelocityHitPriorityID = "swiftcore/VelocityHitPriority::hitPriority"

@MainActor
func drawerVelocityBlankClickDeselects(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[2].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    let baseline = DocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    report.expectEqual(
        expected: [100, 64, 32], actual: notes.map { fixture.handle($0)?.value ?? -1 },
        cppID: drawerVelocityClickSelectionID, what: "the published handles preserve the pre-click fixture values")
    let depth = document.history.undoCount
    let blankX = page.plotWidth - 1 / page.devicePixelRatio
    let blankY = page.axisModel.velocityToY(40)
    let consumed = page.pointerPress(x: blankX, y: blankY, surface: 1, button: 1, modifiers: 0)
    report.expect(consumed, cppID: drawerVelocityClickSelectionID, message: "a blank plot press is consumed")
    report.expect(page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a blank press holds a live gesture")
    report.expect(
        fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id], cppID: drawerVelocityClickSelectionID,
        message: "a blank press keeps the selection until release")
    report.expect(
        page.frozenPreview.isEmpty, cppID: drawerVelocityClickSelectionID, message: "a blank press previews nothing")
    _ = page.pointerRelease(x: blankX, y: blankY, button: 1)
    report.expect(
        fixture.session.selectedNoteOrder.isEmpty, cppID: drawerVelocityClickSelectionID,
        message: "a blank release clears the selection")
    report.expect(!page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a blank release ends the gesture")
    report.expect(
        DocumentSnapshot(document) == baseline, cppID: drawerVelocityTransactionID,
        message: "deselecting on release writes nothing")
    report.expectEqual(
        expected: depth, actual: document.history.undoCount,
        cppID: drawerVelocityClickSelectionID, what: "a cancelled gesture leaves the undo depth unchanged")
    report.expectEqual(
        expected: [100, 64, 32], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
        cppID: drawerVelocityClickSelectionID, what: "a blank click preserves the timeline projection")
    for (index, note) in notes.enumerated() {
        report.expectEqual(
            expected: captured[index], actual: document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID,
            what: "a blank click leaves every velocity captured")
    }
    for note in notes {
        report.expectEqual(
            expected: Int(document.note(note.id)?.velocity ?? 0), actual: fixture.handle(note)?.value ?? -1,
            cppID: drawerVelocityClickSelectionID, what: "a blank click republishes every captured value")
    }
}

@MainActor
func drawerVelocityGraduationClickEdits(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    guard let maximum = page.axisModel.labels.first(where: { $0.velocity == 127 }) else {
        report.fail(drawerVelocityClickSelectionID, "the ruler published no 127 label")
        return
    }
    let expected = page.axisModel.rulerVelocityAt(y: maximum.y, labelHeight: page.axisModel.geometry.labelHeight)
    guard expected >= 1 else {
        report.fail(drawerVelocityClickSelectionID, "the 127 label row resolved no velocity")
        return
    }
    let baseline = DocumentSnapshot(document)
    let depth = document.history.undoCount
    let publications = drawerVelocityPublicationCounter(session: fixture.session)
    report.expectEqual(
        expected: [100, 64, 32], actual: notes.map { fixture.handle($0)?.value ?? -1 },
        cppID: drawerVelocityClickSelectionID, what: "the published handles preserve the pre-click fixture values")
    let untouched = document.note(notes[2].id)?.velocity
    let consumed = page.pointerPress(x: 10, y: maximum.y, surface: 0, button: 1, modifiers: 0)
    report.expect(consumed, cppID: drawerVelocityClickSelectionID, message: "a graduation press is consumed")
    report.expectEqual(
        expected: expected, actual: Int(document.note(notes[0].id)?.velocity ?? 0),
        cppID: drawerVelocityClickSelectionID, what: "a graduation click sets the first selected note")
    report.expectEqual(
        expected: expected, actual: Int(document.note(notes[1].id)?.velocity ?? 0),
        cppID: drawerVelocityClickSelectionID, what: "a graduation click sets the second selected note")
    report.expectEqual(
        expected: untouched, actual: document.note(notes[2].id)?.velocity, cppID: drawerVelocityClickSelectionID,
        what: "a graduation click leaves the unselected note alone")
    report.expectEqual(
        expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityTransactionID,
        what: "one graduation click makes one revision")
    report.expect(
        document.history.currentIdentity != baseline.identity, cppID: drawerVelocityTransactionID,
        message: "one graduation click makes one history entry")
    report.expect(
        fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityClickSelectionID,
        message: "a graduation click keeps the selection")
    report.expectEqual(
        expected: depth + 1, actual: document.history.undoCount,
        cppID: drawerVelocityClickSelectionID, what: "one release grows the undo depth by exactly one")
    report.expectEqual(
        expected: [expected, expected, 32],
        actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
        cppID: drawerVelocityClickSelectionID,
        what: "a released drag republishes the staged velocities into the timeline projection")
    report.expectEqual(
        expected: 1, actual: publications.document, cppID: drawerVelocityClickSelectionID,
        what: "one release publishes exactly one document change")
    report.expectEqual(
        expected: 1, actual: publications.dirty, cppID: drawerVelocityClickSelectionID,
        what: "one release publishes exactly one dirty change")
    let released = page.pointerRelease(x: 10, y: maximum.y, button: 1)
    report.expect(
        !released, cppID: drawerVelocityClickSelectionID, message: "the release after a graduation commit is inert")
    report.expectEqual(
        expected: expected, actual: fixture.handle(notes[0])?.value ?? -1, cppID: drawerVelocityClickSelectionID,
        what: "the first handle republishes the clicked graduation")
    report.expectEqual(
        expected: expected, actual: fixture.handle(notes[1])?.value ?? -1, cppID: drawerVelocityClickSelectionID,
        what: "the second handle republishes the clicked graduation")
}

@MainActor
func drawerVelocityClickBelowNodeCommits(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    let originalLater = notes[2]
    _ = document.setVelocities(
        [NoteVelocity(noteID: originalLater.id, velocity: 96)],
        expectedRevision: document.revision)
    page.refreshFromDocument()
    guard let later = document.note(originalLater.id) else {
        report.fail(drawerVelocityClickSelectionID, "the reseeded later note is missing")
        return
    }
    page.setUseDetents(enabled: false)
    fixture.session.setSelectedNotes([later.id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [later.id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    guard let laterHandle = fixture.handle(later) else {
        report.fail(drawerVelocityClickSelectionID, "the fixture's later note has no published handle")
        return
    }
    let baseline = DocumentSnapshot(document)
    let depth = document.history.undoCount
    let publications = drawerVelocityPublicationCounter(session: fixture.session)
    report.expectEqual(
        expected: [100, 64, 96], actual: notes.map { fixture.handle($0)?.value ?? -1 },
        cppID: drawerVelocityClickSelectionID, what: "the published handles preserve the pre-click fixture values")
    let pressX = laterHandle.x
    let pressedLiteral = 40
    let pressY = page.axisModel.velocityToY(pressedLiteral)
    _ = page.pointerPress(x: pressX, y: pressY, surface: 1, button: 1, modifiers: 0)
    let pressPreview = Int(page.frozenPreview[later.id] ?? 0)
    report.expectEqual(
        expected: pressedLiteral, actual: pressPreview,
        cppID: drawerVelocityClickSelectionID,
        what: "the off-node preview equals the independently chosen pressed literal")
    report.expect(
        page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "an off-node press holds a live gesture")
    report.expect(
        fixture.session.selectedNoteOrder == [later.id], cppID: drawerVelocityClickSelectionID,
        message: "an off-node press previews without changing the selection")
    _ = page.pointerRelease(x: pressX, y: pressY, button: 1)
    report.expectEqual(
        expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityTransactionID,
        what: "one off-node click makes one revision")
    report.expect(
        document.history.currentIdentity != baseline.identity, cppID: drawerVelocityTransactionID,
        message: "one off-node click makes one history entry")
    report.expectEqual(
        expected: pressedLiteral, actual: Int(document.note(later.id)?.velocity ?? 0),
        cppID: drawerVelocityClickSelectionID,
        what: "the off-node commit equals the independently chosen pressed literal")
    report.expectEqual(
        expected: pressPreview, actual: Int(document.note(later.id)?.velocity ?? 0),
        cppID: drawerVelocityClickSelectionID,
        what: "the release commits the pressed preview")
    report.expectEqual(
        expected: notes[0].velocity, actual: document.note(notes[0].id)?.velocity,
        cppID: drawerVelocityClickSelectionID, what: "an off-node click leaves the first note alone")
    report.expectEqual(
        expected: notes[1].velocity, actual: document.note(notes[1].id)?.velocity,
        cppID: drawerVelocityClickSelectionID, what: "an off-node click leaves the second note alone")
    report.expect(
        fixture.session.selectedNoteOrder == [later.id], cppID: drawerVelocityClickSelectionID,
        message: "an off-node click keeps its own selection")
    report.expect(
        !page.hasGesture && page.frozenPreview.isEmpty, cppID: drawerVelocityClickSelectionID,
        message: "an off-node release ends the gesture")
    report.expectEqual(
        expected: depth + 1, actual: document.history.undoCount,
        cppID: drawerVelocityClickSelectionID, what: "one release grows the undo depth by exactly one")
    report.expectEqual(
        expected: 1, actual: publications.document, cppID: drawerVelocityClickSelectionID,
        what: "one release publishes exactly one document change")
    report.expectEqual(
        expected: 1, actual: publications.dirty, cppID: drawerVelocityClickSelectionID,
        what: "one release publishes exactly one dirty change")
    report.expectEqual(
        expected: [100, 64, 40], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
        cppID: drawerVelocityClickSelectionID,
        what: "a released drag republishes the staged velocities into the timeline projection")
}

@MainActor
func drawerVelocityBandExpandContract(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityClickSelectionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[2].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[2].id] else {
        report.fail(drawerVelocityClickSelectionID, "the press-time selection did not latch")
        return
    }
    guard let first = fixture.handle(notes[0]), let second = fixture.handle(notes[1]),
        let third = fixture.handle(notes[2])
    else {
        report.fail(drawerVelocityClickSelectionID, "the fixture's notes have no published handles")
        return
    }
    let contractedX = (second.x + third.x) / 2
    guard contractedX > second.x, contractedX < third.x, first.x < contractedX else {
        report.fail(drawerVelocityClickSelectionID, "the contracted band cannot split the published handles")
        return
    }
    let baseline = DocumentSnapshot(document)
    let depth = document.history.undoCount
    let captured = notes.map { document.note($0.id)?.velocity }
    let pressed = page.pointerPress(x: 0, y: 0, surface: 1, button: 2, modifiers: 0)
    report.expect(pressed, cppID: drawerVelocityClickSelectionID, message: "a band press is consumed")
    report.expect(page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a band press holds a live gesture")
    _ = page.pointerMove(x: 400, y: 120, buttons: 2)
    _ = page.pointerMove(x: contractedX, y: 120, buttons: 2)
    _ = page.pointerRelease(x: contractedX, y: 120, button: 2)
    report.expect(
        fixture.session.selectedNotes == Set([notes[0].id, notes[1].id]), cppID: drawerVelocityClickSelectionID,
        message: "the contracted band keeps the covered pair and drops the later note")
    report.expect(!page.hasGesture, cppID: drawerVelocityClickSelectionID, message: "a band release ends the gesture")
    report.expect(
        DocumentSnapshot(document) == baseline, cppID: drawerVelocityTransactionID,
        message: "a band selection writes nothing")
    report.expectEqual(
        expected: depth, actual: document.history.undoCount,
        cppID: drawerVelocityClickSelectionID, what: "a cancelled gesture leaves the undo depth unchanged")
    report.expectEqual(
        expected: [100, 64, 32], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
        cppID: drawerVelocityClickSelectionID, what: "a band selection preserves the timeline projection")
    for (index, note) in notes.enumerated() {
        report.expectEqual(
            expected: captured[index], actual: document.note(note.id)?.velocity, cppID: drawerVelocityClickSelectionID,
            what: "a band selection leaves every velocity captured")
    }
}

@MainActor
func drawerVelocityStackedHitPriority(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityHitPriorityID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    let overlapIDs = try? document.addNotes([
        NewNote(track: 0, tick: 12, pitch: 61, duration: 24, velocity: notes[0].velocity)
    ])
    guard let overlapID = overlapIDs?.first else {
        report.fail(drawerVelocityHitPriorityID, "the overlap note was not inserted")
        return
    }
    page.refreshFromDocument()
    guard let overlap = document.notes(in: 0).first(where: { $0.id == overlapID }) else {
        report.fail(drawerVelocityHitPriorityID, "the overlap note did not resolve")
        return
    }
    guard let circles = fixture.handle(overlap), let stem = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityHitPriorityID, "the stacked notes have no published handles")
        return
    }
    guard abs(circles.y - stem.y) < 0.001 else {
        report.fail(drawerVelocityHitPriorityID, "the overlap published off the target level")
        return
    }
    let gapX = circles.x - stem.x
    let gapY = circles.y - stem.y
    guard gapX * gapX + gapY * gapY > circles.hitRadius * circles.hitRadius else {
        report.fail(drawerVelocityHitPriorityID, "the overlap circle covers the target node")
        return
    }
    guard circles.x > stem.x, circles.x < stem.endX else {
        report.fail(drawerVelocityHitPriorityID, "the overlap sits outside the target stem")
        return
    }
    report.expectEqual(
        expected: Int(notes[0].velocity), actual: Int(document.note(overlapID)?.velocity ?? 0),
        cppID: drawerVelocityHitPriorityID, what: "the overlap note carries the target velocity")
    let baseline = DocumentSnapshot(document)
    let capturedOverlap = document.note(overlapID)?.velocity
    let captured = notes.map { document.note($0.id)?.velocity }
    fixture.session.setSelectedNotes([overlapID])
    page.refreshFromDocument()
    report.expect(
        fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID,
        message: "the overlap selection latches before the press")
    let selectedPress = page.pointerPress(x: circles.x, y: circles.y, surface: 1, button: 1, modifiers: 0)
    report.expect(
        selectedPress, cppID: drawerVelocityHitPriorityID, message: "pressing the selected circle is consumed")
    report.expect(
        page.hasGesture, cppID: drawerVelocityHitPriorityID,
        message: "pressing the selected circle holds a live gesture")
    report.expect(
        fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID,
        message: "pressing the selected circle keeps it over the stem")
    _ = page.pointerRelease(x: circles.x, y: circles.y, button: 1)
    report.expect(
        fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID,
        message: "releasing the selected circle keeps it")
    report.expect(
        DocumentSnapshot(document) == baseline, cppID: drawerVelocityHitPriorityID,
        message: "a circle-over-stem click writes nothing")
    report.expectEqual(
        expected: [100, 64, 32, 100],
        actual: (notes.map(\.id) + [overlapID]).map { drawerVelocityTimelineVelocity(fixture.session, $0) },
        cppID: drawerVelocityHitPriorityID,
        what: "a selected circle-over-stem click preserves the timeline projection")
    fixture.session.setSelectedNotes([notes[0].id])
    page.refreshFromDocument()
    report.expect(
        fixture.session.selectedNoteOrder == [notes[0].id], cppID: drawerVelocityHitPriorityID,
        message: "the stem selection latches before the press")
    let unselectedPress = page.pointerPress(x: circles.x, y: circles.y, surface: 1, button: 1, modifiers: 0)
    report.expect(
        unselectedPress, cppID: drawerVelocityHitPriorityID, message: "pressing the unselected circle is consumed")
    report.expect(
        page.hasGesture, cppID: drawerVelocityHitPriorityID,
        message: "pressing the unselected circle holds a live gesture")
    report.expect(
        fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID,
        message: "an unselected circle wins over a selected stem")
    _ = page.pointerRelease(x: circles.x, y: circles.y, button: 1)
    report.expect(
        fixture.session.selectedNoteOrder == [overlapID], cppID: drawerVelocityHitPriorityID,
        message: "releasing the winning circle keeps it")
    report.expect(
        DocumentSnapshot(document) == baseline, cppID: drawerVelocityHitPriorityID,
        message: "a circle-over-stem reselect writes nothing")
    report.expectEqual(
        expected: [100, 64, 32, 100],
        actual: (notes.map(\.id) + [overlapID]).map { drawerVelocityTimelineVelocity(fixture.session, $0) },
        cppID: drawerVelocityHitPriorityID,
        what: "an unselected circle wins without changing the timeline projection")
    report.expectEqual(
        expected: capturedOverlap, actual: document.note(overlapID)?.velocity, cppID: drawerVelocityHitPriorityID,
        what: "hit-priority clicks leave the overlap velocity captured")
    for (index, note) in notes.enumerated() {
        report.expectEqual(
            expected: captured[index], actual: document.note(note.id)?.velocity, cppID: drawerVelocityHitPriorityID,
            what: "hit-priority clicks leave every velocity captured")
    }
}

@MainActor
func drawerVelocityStemPressKeepsSelection(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityHitPriorityID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[0].id] else {
        report.fail(drawerVelocityHitPriorityID, "the press-time selection did not latch")
        return
    }
    guard let stem = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityHitPriorityID, "the fixture's target note has no published handle")
        return
    }
    let stemX = stem.x + stem.hitRadius + 2
    guard stem.endX - stem.x >= stem.hitRadius + 3 else {
        report.fail(drawerVelocityHitPriorityID, "the target stem spans less than one hit diameter")
        return
    }
    for handle in fixture.handles where handle.noteIdText != stem.noteIdText {
        let dx = handle.x - stemX
        let dy = handle.y - stem.y
        if dx * dx + dy * dy <= handle.hitRadius * handle.hitRadius {
            report.fail(drawerVelocityHitPriorityID, "the stem point touches another node")
            return
        }
    }
    let baseline = DocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    let consumed = page.pointerPress(x: stemX, y: stem.y, surface: 1, button: 1, modifiers: 0)
    report.expect(consumed, cppID: drawerVelocityHitPriorityID, message: "a stem-only press is consumed")
    report.expect(
        page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "a stem-only press holds a live gesture")
    report.expect(
        fixture.session.selectedNoteOrder == [notes[0].id], cppID: drawerVelocityHitPriorityID,
        message: "a stem-only press keeps the selected stem")
    _ = page.pointerRelease(x: stemX, y: stem.y, button: 1)
    report.expect(
        fixture.session.selectedNoteOrder == [notes[0].id], cppID: drawerVelocityHitPriorityID,
        message: "releasing the stem keeps it")
    report.expect(
        DocumentSnapshot(document) == baseline, cppID: drawerVelocityHitPriorityID,
        message: "a stem-only click writes nothing")
    report.expectEqual(
        expected: [100, 64, 32],
        actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
        cppID: drawerVelocityHitPriorityID,
        what: "a stem-only click preserves the timeline projection")
    for (index, note) in notes.enumerated() {
        report.expectEqual(
            expected: captured[index], actual: document.note(note.id)?.velocity, cppID: drawerVelocityHitPriorityID,
            what: "a stem-only click leaves every velocity captured")
    }
}

@MainActor
func drawerVelocityMovedNodeNoClickThrough(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityHitPriorityID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.clearSelectedNotes()
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder.isEmpty else {
        report.fail(drawerVelocityHitPriorityID, "the selection did not clear")
        return
    }
    guard let near = fixture.handle(notes[1]), let far = fixture.handle(notes[2]) else {
        report.fail(drawerVelocityHitPriorityID, "the fixture's notes have no published handles")
        return
    }
    let baseline = DocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    _ = page.pointerPress(x: far.x, y: far.y, surface: 1, button: 1, modifiers: 0)
    report.expect(
        fixture.session.selectedNoteOrder == [notes[2].id], cppID: drawerVelocityHitPriorityID,
        message: "pressing a node selects it")
    report.expect(page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "pressing a node holds a live gesture")
    var step = 0.0
    for candidate in [3.0, 4.0, 5.0, 2.0, -3.0, -4.0] {
        if page.axisModel.yToLevel(far.y + candidate) == page.axisModel.yToLevel(far.y),
            abs(candidate) > far.hitRadius / 6
        {
            step = candidate
            break
        }
    }
    guard step != 0 else {
        report.fail(drawerVelocityHitPriorityID, "no same-level step leaves the activation distance")
        return
    }
    let endX = near.x
    let endY = far.y + step
    _ = page.pointerMove(x: endX, y: endY, buttons: 1)
    report.expectEqual(
        expected: Int(notes[2].velocity), actual: Int(page.frozenPreview[notes[2].id] ?? 0),
        cppID: drawerVelocityHitPriorityID, what: "a same-level move previews the captured velocity")
    report.expectEqual(
        expected: [100, 64, 32],
        actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
        cppID: drawerVelocityHitPriorityID,
        what: "a same-level gesture previews without changing the timeline projection")
    _ = page.pointerRelease(x: endX, y: endY, button: 1)
    report.expect(
        !page.hasGesture && page.frozenPreview.isEmpty, cppID: drawerVelocityHitPriorityID,
        message: "a same-value move ends the gesture with no preview left")
    report.expect(
        DocumentSnapshot(document) == baseline, cppID: drawerVelocityTransactionID,
        message: "a same-value move writes nothing")
    report.expect(
        fixture.session.selectedNoteOrder == [notes[2].id], cppID: drawerVelocityHitPriorityID,
        message: "releasing over another column does not click through")
    report.expectEqual(
        expected: [100, 64, 32],
        actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
        cppID: drawerVelocityHitPriorityID,
        what: "a moved node releases without changing the timeline projection")
    for (index, note) in notes.enumerated() {
        report.expectEqual(
            expected: captured[index], actual: document.note(note.id)?.velocity, cppID: drawerVelocityHitPriorityID,
            what: "a moved node leaves every velocity captured")
    }
}

@MainActor
func drawerVelocityRightPressPreservesGroup(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityHitPriorityID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[2].id])
    page.refreshFromDocument()
    guard fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id] else {
        report.fail(drawerVelocityHitPriorityID, "the press-time selection did not latch")
        return
    }
    guard let lead = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityHitPriorityID, "the fixture's lead note has no published handle")
        return
    }
    let baseline = DocumentSnapshot(document)
    let captured = notes.map { document.note($0.id)?.velocity }
    let consumed = page.pointerPress(x: lead.x, y: lead.y, surface: 1, button: 2, modifiers: 0)
    report.expect(consumed, cppID: drawerVelocityHitPriorityID, message: "a secondary press on the group is consumed")
    report.expect(
        page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "a secondary press holds a live gesture")
    report.expect(
        fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id], cppID: drawerVelocityHitPriorityID,
        message: "a secondary press preserves the selected group")
    _ = page.pointerRelease(x: lead.x, y: lead.y, button: 2)
    report.expect(
        fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id], cppID: drawerVelocityHitPriorityID,
        message: "a secondary release preserves the selected group")
    report.expect(!page.hasGesture, cppID: drawerVelocityHitPriorityID, message: "a secondary release ends the gesture")
    report.expect(
        DocumentSnapshot(document) == baseline, cppID: drawerVelocityHitPriorityID,
        message: "a secondary click writes nothing")
    report.expectEqual(
        expected: [100, 64, 32],
        actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
        cppID: drawerVelocityHitPriorityID,
        what: "a secondary group click preserves the timeline projection")
    for (index, note) in notes.enumerated() {
        report.expectEqual(
            expected: captured[index], actual: document.note(note.id)?.velocity, cppID: drawerVelocityHitPriorityID,
            what: "a secondary click leaves every velocity captured")
    }
}
