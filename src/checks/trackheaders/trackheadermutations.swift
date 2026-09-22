import Foundation
import PorydawApp
import PorydawCore

@MainActor
func renameCommitsAndRebuildsHeader(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::renameCommitsAndRebuildsHeader"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let baseline = HeaderDocumentBaseline(fx.document)
    let p = fx.point(.title)
    report.expect(h.doublePointer(x: p.x, y: p.y, button: 1, modifiers: 0),
                  cppID: id, message: "title double click opens rename")
    report.expectEqual(0, h.renamingTrack, cppID: id, what: "rename targets clicked track")
    h.renameDraft = "Discard direct cancellation"
    h.finishRename(commit: false, restoreRollFocus: false)
    report.expectEqual(-1, h.renamingTrack, cppID: id, what: "cancel closes editor")
    h.beginRename(track: 0)
    h.renameDraft = "Discard transient cancellation"
    h.inputCancelled(reason: 2)
    h.finishRename(commit: true, restoreRollFocus: false)
    report.expectEqual(-1, h.renamingTrack, cppID: id, what: "hidden cancels draft permanently")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "rename cancellation")
    var focusRestores = 0
    h.onRestoreRollFocus = { focusRestores += 1 }
    h.beginRename(track: 0)
    h.renameDraft = "HdrSrc"
    h.finishRename(commit: true, restoreRollFocus: true)
    report.expectEqual(-1, h.renamingTrack, cppID: id, what: "commit closes editor")
    report.expectEqual(1, focusRestores, cppID: id, what: "commit restores requested roll focus")
    report.expectEqual("HdrSrc", fx.document.trackName(0), cppID: id, what: "commit renames song track")
    report.expectEqual(baseline.revision + 1, fx.document.revision, cppID: id,
                       what: "rename is one document edit")
    fx.rebuild()
    report.expectEqual("1 · HdrSrc", h.rows[0].title, cppID: id,
                       what: "renamed title survives presenter rebuild")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "rename undo succeeds")
    report.expectEqual(baseline.state, fx.document.state, cppID: id, what: "one undo restores name")
}

@MainActor
func reorderCommitsAndRebuildsHeader(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::reorderCommitsAndRebuildsHeader"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let initial = HeaderDocumentBaseline(fx.document)
    let start = fx.point(.title)
    let bottom = Double(fx.trackRows.count * h.rowHeight)
    for reason in 0...3 {
        _ = h.beginPointer(x: start.x, y: start.y, button: 1, modifiers: 0)
        _ = h.updatePointer(x: start.x, y: bottom, modifiers: 0)
        report.expect(h.reorderIndicatorVisible, cppID: id,
                      message: "cancel \(reason): drag displays insertion marker")
        report.expectEqual(bottom, h.reorderIndicatorY, cppID: id,
                           what: "cancel \(reason): marker reaches bottom insertion slot")
        h.inputCancelled(reason: reason)
        report.expect(!h.reorderIndicatorVisible, cppID: id,
                      message: "cancel \(reason): marker clears")
        report.expect(!h.endPointer(x: start.x, y: bottom, button: 1, modifiers: 0),
                      cppID: id, message: "cancel \(reason): late release is rejected")
        initial.expectUnchanged(report, fx.document, cppID: id, phase: "reorder cancel \(reason)")
    }
    _ = h.beginPointer(x: start.x, y: start.y, button: 1, modifiers: 0)
    _ = h.updatePointer(x: start.x, y: bottom, modifiers: 0)
    _ = h.endPointer(x: start.x, y: bottom, button: 2, modifiers: 0)
    initial.expectUnchanged(report, fx.document, cppID: id, phase: "wrong-button reorder release")

    let notes = fx.document.notes(in: 0).map { "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)" }
    fx.session.mutedTracks = [0]
    h.refreshFromDocument()
    h.beginRename(track: 0)
    h.renameDraft = "Dragged"
    _ = h.beginPointer(x: start.x, y: start.y, button: 1, modifiers: 0)
    _ = h.updatePointer(x: start.x, y: bottom, modifiers: 0)
    _ = h.endPointer(x: start.x, y: bottom, button: 1, modifiers: 0)
    report.expectEqual("Dragged", fx.document.trackName(1), cppID: id,
                       what: "drag commits pending name before moving its track")
    report.expectEqual(notes, fx.document.notes(in: 1).map {
        "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)"
    }, cppID: id, what: "reorder carries musical content to destination")
    report.expectEqual(Set([1]), fx.session.mutedTracks, cppID: id, what: "mute follows moved identity")
    report.expectEqual([1], fx.trackRows.filter(\.muteChecked).map(\.track), cppID: id,
                       what: "moved row displays migrated mute")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "move undo succeeds")
    report.expectEqual(Set([0]), fx.session.mutedTracks, cppID: id, what: "undo restores mute identity")
    report.expectEqual("Dragged", fx.document.trackName(0), cppID: id,
                       what: "move undo retains earlier committed rename")
    report.expect(fx.document.history.redoDocument(), cppID: id, message: "move redo succeeds")
    report.expectEqual(Set([1]), fx.session.mutedTracks, cppID: id, what: "redo moves mute again")
    fx.rebuild()
    report.expectEqual("2 · Dragged", h.rows[1].title, cppID: id,
                       what: "moved title survives rebuild at new numbered slot")
}

@MainActor
func addTrackOpensPickerAndRebuildsHeader(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::addTrackOpensPickerAndRebuildsHeader"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let baseline = HeaderDocumentBaseline(fx.document)
    let add = fx.point(.add, row: 2)
    var requests = 0
    h.onAddTrackRequested = { requests += 1 }
    h.updateHover(x: add.x, y: add.y)
    report.expect(h.rows[2].addHovered, cppID: id, message: "add row displays hover")
    h.clearHover()
    report.expect(!h.rows[2].addHovered, cppID: id, message: "leave clears add hover")
    _ = h.beginPointer(x: add.x, y: add.y, button: 2, modifiers: 0)
    report.expect(!h.menuOpen && requests == 0, cppID: id,
                  message: "right press on add row opens neither menu nor picker")
    report.expectEqual(0, fx.session.selectedTrack, cppID: id, what: "add row preserves selection")
    _ = h.beginPointer(x: add.x, y: add.y, button: 1, modifiers: 0)
    report.expect(h.rows[2].addPressed, cppID: id, message: "left press depresses add row")
    h.inputCancelled(reason: 0)
    report.expect(!h.rows[2].addPressed, cppID: id, message: "FocusLost releases add row")
    report.expect(!h.endPointer(x: add.x, y: add.y, button: 1, modifiers: 0),
                  cppID: id, message: "late add release is rejected")
    _ = h.beginPointer(x: add.x, y: add.y, button: 1, modifiers: 0)
    _ = h.endPointer(x: add.x, y: add.y - Double(h.rowHeight), button: 1, modifiers: 0)
    report.expectEqual(0, requests, cppID: id, what: "release outside add row requests no picker")
    fx.click(report, .add, row: 2, cppID: id)
    report.expectEqual(1, requests, cppID: id, what: "add click requests existing voice picker")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "picker opened")
    h.completeVoiceRequest(program: -1)
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "picker cancelled")
    fx.click(report, .add, row: 2, cppID: id)
    report.expectEqual(2, requests, cppID: id, what: "picker can reopen after cancellation")
    h.completeVoiceRequest(program: 127)
    report.expectEqual(3, fx.document.engineTracks.usedTrackCount, cppID: id,
                       what: "picker acceptance creates one engine track")
    report.expectEqual(2, fx.session.selectedTrack, cppID: id, what: "new track becomes primary")
    report.expectEqual([127], fx.document.lanePoints(track: 2, lane: .voice).map(\.value),
                       cppID: id, what: "new track receives accepted program")
    report.expectEqual(baseline.revision + 1, fx.document.revision, cppID: id,
                       what: "accepted add writes once")
    let accepted = fx.document.state
    h.completeVoiceRequest(program: 126)
    report.expectEqual(accepted, fx.document.state, cppID: id, what: "completion is single use")
    fx.rebuild()
    report.expectEqual([0, 1, 2], fx.trackRows.map(\.track), cppID: id,
                       what: "rebuilt tracks remain ordered and unique")
    report.expectEqual(4, h.rows.count, cppID: id, what: "rebuilt add row follows three tracks")
    report.expect(h.rows[3].isAddTrack, cppID: id, message: "add row remains last")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "add undo succeeds")
    report.expectEqual(baseline.state, fx.document.state, cppID: id, what: "one undo removes added track")
    report.expectEqual(3, h.rows.count, cppID: id, what: "undo restores prior rows")
    report.expect(fx.document.history.redoDocument(), cppID: id, message: "add redo succeeds")
    report.expectEqual(accepted, fx.document.state, cppID: id, what: "redo restores accepted track")

    // A picker completion arriving after remap cannot edit the replacement raw slot.
    var voiceRequests: [Int] = []
    h.onChangeTrackVoiceRequested = { voiceRequests.append($0) }
    let voice = fx.point(.voice)
    _ = h.doublePointer(x: voice.x, y: voice.y, button: 1, modifiers: 0)
    report.expectEqual([0], voiceRequests, cppID: id, what: "voice double click requests picker")
    report.expect(fx.document.moveTrack(0, to: 1), cppID: id, message: "picker target remaps")
    let remapped = HeaderDocumentBaseline(fx.document)
    h.completeVoiceRequest(program: 127)
    remapped.expectUnchanged(report, fx.document, cppID: id, phase: "stale voice completion")
}
