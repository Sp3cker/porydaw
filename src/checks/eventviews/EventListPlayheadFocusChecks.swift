import Foundation
import PorydawApp
import PorydawAppEventList
import PorydawCore

@MainActor
internal func focusCommitsCursor(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .basic)
    // A007: direct fixture construction replaces the native rig-open guard.
    report.expect(fixture.session.document.rawChunks.indices.contains(0), cppID: focusCommitsCursorID,
                  message: "A007 basic fixture has a primary chunk")
    // A008: attachment replaces the native EventWidgets lookup guard.
    report.expect(fixture.presenter.attached, cppID: focusCommitsCursorID,
                  message: "A008 event-list presenter is attached")

    let eventRow = rowFor(fixture.presenter, tick: 70, kind: .noteOn)
    // A009: the NoteOn row lookup succeeds in the fixture.
    report.expect(eventRow != nil, cppID: focusCommitsCursorID,
                  message: "A009 NoteOn row at tick 70 exists")
    guard let eventRow else { return }

    fixture.presenter.focusRow(row: eventRow)
    // A010: focusing an event commits its tick to the session edit cursor.
    report.expectEqual(expected: Tick(70), actual: fixture.session.editCursor, cppID: focusCommitsCursorID,
                       what: "A010 focusing NoteOn commits tick 70")

    fixture.presenter.focusRow(row: fixture.presenter.rowCount - 1)
    // A011: focusing the sentinel commits the chunk end tick.
    report.expectEqual(expected: Tick(120), actual: fixture.session.editCursor, cppID: focusCommitsCursorID,
                       what: "A011 focusing EOT commits end tick 120")
}

@MainActor
internal func focusedSiblingWins(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .basic)
    // A012: direct fixture construction replaces the native rig-open guard.
    report.expect(fixture.session.document.rawChunks.indices.contains(0), cppID: focusedSiblingWinsID,
                  message: "A012 basic fixture has a primary chunk")
    // A013: attachment replaces the native EventWidgets lookup guard.
    report.expect(fixture.presenter.attached && fixture.presenter.rowCount > 0,
                  cppID: focusedSiblingWinsID, message: "A013 event-list presenter is attached")

    let first = rowFor(fixture.presenter, tick: 60, kind: .cc)
    // A014: the first CC row at the duplicate tick exists.
    report.expect(first != nil, cppID: focusedSiblingWinsID,
                  message: "A014 first CC row at tick 60 exists")
    guard let first else { return }

    let sibling = first + 1
    // A015: the immediately following row is the same-tick sibling.
    report.expect(sibling < fixture.presenter.rowCount
        && fixture.presenter.rowTick(row: sibling) == 60,
        cppID: focusedSiblingWinsID, message: "A015 adjacent sibling retains tick 60")
    guard sibling < fixture.presenter.rowCount else { return }

    fixture.presenter.setPlayheadTick(tick: -1, playing: false)
    fixture.presenter.focusRow(row: first)
    fixture.presenter.setPlayheadTick(tick: 60, playing: false)
    // A016: the focused first sibling wins exact-tick snapping.
    report.expectEqual(expected: first, actual: fixture.presenter.playRow, cppID: focusedSiblingWinsID,
                       what: "A016 focused first sibling wins at tick 60")
    // A017: tint follows the focused first sibling.
    report.expect(tintedRows(fixture.presenter) == [first]
        && hasExactTintContract(fixture.presenter, expected: first),
        cppID: focusedSiblingWinsID, message: "A017 first sibling is the only tinted row")

    fixture.presenter.setPlayheadTick(tick: 59.999, playing: false)
    // A018: the same focused sibling wins within the half-tick tolerance.
    report.expectEqual(expected: first, actual: fixture.presenter.playRow, cppID: focusedSiblingWinsID,
                       what: "A018 focused first sibling wins within 0.5 tick")

    fixture.presenter.focusRow(row: sibling)
    // A019: moving focus to the sibling moves the play row immediately.
    report.expectEqual(expected: sibling, actual: fixture.presenter.playRow, cppID: focusedSiblingWinsID,
                       what: "A019 focusing sibling moves playRow")
    // A020: tint follows the newly focused sibling.
    report.expect(tintedRows(fixture.presenter) == [sibling]
        && hasExactTintContract(fixture.presenter, expected: sibling),
        cppID: focusedSiblingWinsID, message: "A020 sibling is the only tinted row")

    let other = rowFor(fixture.presenter, tick: 70, kind: .noteOn)
    // A021: an unrelated event row exists for the no-snap phase.
    report.expect(other != nil, cppID: focusedSiblingWinsID,
                  message: "A021 unrelated NoteOn row at tick 70 exists")
    guard let other else { return }

    fixture.presenter.focusRow(row: other)
    fixture.presenter.setPlayheadTick(tick: 60, playing: false)
    let expected = playheadRowOracle(fixture.presenter.model.rows, tick: 60)
    // A022: once an unrelated row is focused, the ordinary oracle wins.
    report.expectEqual(expected: expected, actual: fixture.presenter.playRow, cppID: focusedSiblingWinsID,
                       what: "A022 unrelated focus restores ordinary row oracle")
    // A023: the ordinary oracle row is the only tinted row.
    report.expect(tintedRows(fixture.presenter) == [expected]
        && hasExactTintContract(fixture.presenter, expected: expected),
        cppID: focusedSiblingWinsID, message: "A023 oracle row is the only tinted row")
}

@MainActor
internal func samplePathAndProgrammaticRestore(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let fixture = EventListPlayheadFixture(suite: suite, service: service, shape: .basic)
    // A024: direct fixture construction replaces the native tab-open guard.
    report.expect(fixture.session.document.rawChunks.indices.contains(0),
                  cppID: samplePathAndProgrammaticRestoreID,
                  message: "A024 basic tab fixture has a primary chunk")
    // A025: attachment replaces the native EventWidgets lookup guard.
    report.expect(fixture.presenter.attached && fixture.presenter.rowCount > 0,
                  cppID: samplePathAndProgrammaticRestoreID,
                  message: "A025 event-list presenter is attached")
    // A026: the session timeline is the Swift equivalent of the native timeline lookup.
    report.expect(!fixture.session.timeline.events.isEmpty,
                  cppID: samplePathAndProgrammaticRestoreID,
                  message: "A026 playback timeline exists")

    let rows = fixture.presenter.model.rows
    let endTick = rows.last?.tick ?? 0
    // A027: a fresh list starts without an edit-focused row.
    report.expectEqual(expected: -1, actual: fixture.presenter.currentRow,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A027 fresh list has no focused row")

    fixture.presenter.setPlayheadTick(tick: Double(endTick + 1), playing: false)
    fixture.presenter.setPlayheadTick(tick: 0, playing: false)
    let tickZero = playheadRowOracle(rows, tick: 0)
    // A028: direct programmatic tick updates use the row oracle without focus.
    report.expectEqual(expected: tickZero, actual: fixture.presenter.playRow,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A028 programmatic tick zero uses the oracle row")
    // A029: programmatic restoration updates whole-row tint with the same oracle row.
    report.expect(tintedRows(fixture.presenter) == [tickZero]
        && hasExactTintContract(fixture.presenter, expected: tickZero),
        cppID: samplePathAndProgrammaticRestoreID,
        message: "A029 programmatic tick zero tints only the oracle row")

    let focused = rowFor(fixture.presenter, tick: 70, kind: .noteOn)
    // A030: the focused NoteOn lookup succeeds.
    report.expect(focused != nil, cppID: samplePathAndProgrammaticRestoreID,
                  message: "A030 NoteOn row at tick 70 exists")
    guard let focused else { return }

    fixture.presenter.focusRow(row: focused)
    // A031: focus commits the edit cursor before the document mutation.
    report.expectEqual(expected: Tick(70), actual: fixture.session.editCursor,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A031 focused row commits edit cursor tick 70")
    let cursorBefore = fixture.session.editCursor
    fixture.session.document.insertRawEvent(
        chunk: 0,
        event: .channel(tick: endTick + 50, status: 0xB0, data0: 7, data1: 64))
    // A032: the document publication/rebuild leaves the cursor untouched.
    report.expectEqual(expected: cursorBefore, actual: fixture.session.editCursor,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A032 insert preserves edit cursor")

    _ = fixture.session.document.history.undoDocument()
    // A033: undo publication also leaves the cursor untouched.
    report.expectEqual(expected: cursorBefore, actual: fixture.session.editCursor,
                       cppID: samplePathAndProgrammaticRestoreID,
                       what: "A033 undo preserves edit cursor")
}
