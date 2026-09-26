import Foundation
import PorydawApp
import PorydawCore

@MainActor
func renameTargetRowAndScrolledTitleResolve(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::renameTargetRowAndScrolledTitleResolve"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let target = 1
    h.configureViewport(width: 228, height: Double(h.rowHeight), fontPx: 13, dpr: 1)
    let baseline = HeaderDocumentBaseline(fx.document)
    guard let row = fx.rowForTrack(target) else {
        report.fail(id, "rename target has no header row")
        return
    }
    report.expect(row != 0 && h.rows[row].track == target, cppID: id,
                  message: "rename target row resolves from track identity")
    guard let title = fx.visibleTitlePoint(forTrack: target) else {
        report.fail(id, "scrolled rename target has no visible title point")
        return
    }
    report.expect(h.scrollY > 0 && title.y >= 0 && title.y < h.viewportHeight,
                  cppID: id, message: "target title stays visible after scrolling")
    report.expect(h.doublePointer(x: title.x, y: title.y, button: 1, modifiers: 0),
                  cppID: id, message: "scrolled target title accepts rename double click")
    report.expectEqual(expected: target, actual: h.renamingTrack, cppID: id,
                       what: "scrolled rename opens for the identity-resolved track")
    h.finishRename(commit: false, restoreRollFocus: false)
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "scrolled rename cancelled")
}

@MainActor
func renameMenuTargetsAndBegins(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::renameMenuTargetsAndBegins"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let target = 1
    let baseline = HeaderDocumentBaseline(fx.document)
    fx.openMenu(report, track: target, cppID: id)
    report.expect((0..<h.menuItems.count).contains {
        h.menuItems[$0].actionId == 3 && h.menuItems[$0].text == "Rename track..."
            && h.menuItems[$0].enabled
    }, cppID: id, message: "menu exposes enabled Rename track action")
    h.activateHeaderMenuAction(actionId: 3)
    report.expect(!h.menuOpen, cppID: id, message: "selecting Rename closes the header menu")
    report.expectEqual(expected: target, actual: h.renamingTrack, cppID: id,
                       what: "selecting Rename begins editing menu target")
    h.finishRename(commit: false, restoreRollFocus: false)
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "menu rename cancelled")
}

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
    report.expectEqual(expected: 0, actual: h.renamingTrack, cppID: id, what: "rename targets clicked track")
    h.renameDraft = "Discard direct cancellation"
    h.finishRename(commit: false, restoreRollFocus: false)
    report.expectEqual(expected: -1, actual: h.renamingTrack, cppID: id, what: "cancel closes editor")
    h.beginRename(track: 0)
    h.renameDraft = "Discard transient cancellation"
    h.inputCancelled(reason: 2)
    h.finishRename(commit: true, restoreRollFocus: false)
    report.expectEqual(expected: -1, actual: h.renamingTrack, cppID: id, what: "hidden cancels draft permanently")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "rename cancellation")
    var focusRestores = 0
    h.onRestoreRollFocus = { focusRestores += 1 }
    h.beginRename(track: 0)
    h.renameDraft = "HdrSrc"
    h.finishRename(commit: true, restoreRollFocus: true)
    report.expectEqual(expected: -1, actual: h.renamingTrack, cppID: id, what: "commit closes editor")
    report.expectEqual(expected: 1, actual: focusRestores, cppID: id, what: "commit restores requested roll focus")
    report.expectEqual(expected: "HdrSrc", actual: fx.document.trackName(0), cppID: id, what: "commit renames song track")
    report.expectEqual(expected: baseline.revision + 1, actual: fx.document.revision, cppID: id,
                       what: "rename is one document edit")
    fx.rebuild()
    report.expectEqual(expected: "1 · HdrSrc", actual: h.rows[0].title, cppID: id,
                       what: "renamed title survives presenter rebuild")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "rename undo succeeds")
    report.expectEqual(expected: baseline.state, actual: fx.document.state, cppID: id, what: "one undo restores name")
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
    _ = h.beginPointer(x: start.x, y: start.y, button: 1, modifiers: 0)
    _ = h.updatePointer(x: start.x, y: 0, modifiers: 0)
    report.expect(h.reorderIndicatorVisible, cppID: id,
                  message: "no-op drag displays insertion marker")
    report.expectEqual(expected: 0, actual: h.reorderIndicatorY, cppID: id,
                       what: "no-op drag marker stays at the top insertion slot")
    _ = h.endPointer(x: start.x, y: 0, button: 1, modifiers: 0)
    initial.expectUnchanged(report, fx.document, cppID: id, phase: "no-op reorder drop")
    for reason in 0...3 {
        _ = h.beginPointer(x: start.x, y: start.y, button: 1, modifiers: 0)
        _ = h.updatePointer(x: start.x, y: bottom, modifiers: 0)
        report.expect(h.reorderIndicatorVisible, cppID: id,
                      message: "cancel \(reason): drag displays insertion marker")
        report.expectEqual(expected: bottom, actual: h.reorderIndicatorY, cppID: id,
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
    report.expect(h.endPointer(x: start.x, y: bottom, button: 2, modifiers: 0),
                  cppID: id, message: "wrong-button release consumes the armed drag")
    report.expect(!h.reorderIndicatorVisible, cppID: id,
                  message: "wrong-button release clears the insertion marker")
    initial.expectUnchanged(report, fx.document, cppID: id, phase: "wrong-button reorder release")

    let notes = fx.document.notes(in: 0).map { "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)" }
    report.expect(!notes.isEmpty, cppID: id,
                  message: "the reorder fixture track carries content to move")
    fx.session.mutedTracks = [0]
    h.refreshFromDocument()
    h.beginRename(track: 0)
    h.renameDraft = "Dragged"
    _ = h.beginPointer(x: start.x, y: start.y, button: 1, modifiers: 0)
    _ = h.updatePointer(x: start.x, y: bottom, modifiers: 0)
    _ = h.endPointer(x: start.x, y: bottom, button: 1, modifiers: 0)
    report.expectEqual(expected: "Dragged", actual: fx.document.trackName(1), cppID: id,
                       what: "drag commits pending name before moving its track")
    report.expectEqual(expected: notes, actual: fx.document.notes(in: 1).map {
        "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)"
    }, cppID: id, what: "reorder carries musical content to destination")
    report.expectEqual(expected: Set([1]), actual: fx.session.mutedTracks, cppID: id, what: "mute follows moved identity")
    report.expectEqual(expected: [1], actual: fx.trackRows.filter(\.muteChecked).map(\.track), cppID: id,
                       what: "moved row displays migrated mute")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "move undo succeeds")
    report.expectEqual(expected: Set([0]), actual: fx.session.mutedTracks, cppID: id, what: "undo restores mute identity")
    report.expectEqual(expected: "Dragged", actual: fx.document.trackName(0), cppID: id,
                       what: "move undo retains earlier committed rename")
    report.expect(fx.document.history.redoDocument(), cppID: id, message: "move redo succeeds")
    report.expectEqual(expected: Set([1]), actual: fx.session.mutedTracks, cppID: id, what: "redo moves mute again")
    fx.rebuild()
    report.expectEqual(expected: "2 · Dragged", actual: h.rows[1].title, cppID: id,
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
    report.expect(add.x >= 0 && add.x < h.trackHeaderWidth
                  && add.y - Double(h.rowHeight) >= 0
                  && add.y - Double(h.rowHeight) < h.viewportHeight,
                  cppID: id, message: "the release outside the add row remains inside the header input")
    var requests = 0
    h.onAddTrackRequested = { requests += 1 }
    h.updateHover(x: add.x, y: add.y)
    report.expect(h.rows[2].addHovered, cppID: id, message: "add row displays hover")
    h.clearHover()
    report.expect(!h.rows[2].addHovered, cppID: id, message: "leave clears add hover")
    _ = h.beginPointer(x: add.x, y: add.y, button: 2, modifiers: 0)
    report.expect(!h.menuOpen && requests == 0, cppID: id,
                  message: "right press on add row opens neither menu nor picker")
    report.expectEqual(expected: 0, actual: fx.session.selectedTrack, cppID: id, what: "add row preserves selection")
    _ = h.beginPointer(x: add.x, y: add.y, button: 1, modifiers: 0)
    report.expect(h.rows[2].addPressed, cppID: id, message: "left press depresses add row")
    h.inputCancelled(reason: 0)
    report.expect(!h.rows[2].addPressed, cppID: id, message: "FocusLost releases add row")
    report.expect(!h.endPointer(x: add.x, y: add.y, button: 1, modifiers: 0),
                  cppID: id, message: "late add release is rejected")
    _ = h.beginPointer(x: add.x, y: add.y, button: 1, modifiers: 0)
    _ = h.endPointer(x: add.x, y: add.y - Double(h.rowHeight), button: 1, modifiers: 0)
    report.expectEqual(expected: 0, actual: requests, cppID: id, what: "release outside add row requests no picker")
    report.expect(!h.rows[2].addPressed, cppID: id,
                  message: "outside release clears the add row press")
    fx.click(report, .add, row: 2, cppID: id)
    report.expectEqual(expected: 1, actual: requests, cppID: id, what: "add click requests existing voice picker")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "picker opened")
    h.completeVoiceRequest(program: -1)
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "picker cancelled")
    fx.click(report, .add, row: 2, cppID: id)
    report.expectEqual(expected: 2, actual: requests, cppID: id, what: "picker can reopen after cancellation")
    h.completeVoiceRequest(program: 127)
    report.expectEqual(expected: 3, actual: fx.document.engineTracks.usedTrackCount, cppID: id,
                       what: "picker acceptance creates one engine track")
    report.expectEqual(expected: 2, actual: fx.session.selectedTrack, cppID: id, what: "new track becomes primary")
    report.expectEqual(expected: [127], actual: fx.document.lanePoints(track: 2, lane: .voice).map(\.value),
                       cppID: id, what: "new track receives accepted program")
    report.expectEqual(expected: baseline.revision + 1, actual: fx.document.revision, cppID: id,
                       what: "accepted add writes once")
    let accepted = fx.document.state
    h.completeVoiceRequest(program: 126)
    report.expectEqual(expected: accepted, actual: fx.document.state, cppID: id, what: "completion is single use")
    fx.rebuild()
    report.expectEqual(expected: [0, 1, 2], actual: fx.trackRows.map(\.track), cppID: id,
                       what: "rebuilt tracks remain ordered and unique")
    report.expectEqual(expected: 4, actual: h.rows.count, cppID: id, what: "rebuilt add row follows three tracks")
    report.expect(h.rows[3].isAddTrack, cppID: id, message: "add row remains last")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "add undo succeeds")
    report.expectEqual(expected: baseline.state, actual: fx.document.state, cppID: id, what: "one undo removes added track")
    report.expectEqual(expected: 3, actual: h.rows.count, cppID: id, what: "undo restores prior rows")
    report.expect(fx.document.history.redoDocument(), cppID: id, message: "add redo succeeds")
    report.expectEqual(expected: accepted, actual: fx.document.state, cppID: id, what: "redo restores accepted track")
    report.expectEqual(expected: 4, actual: h.rows.count, cppID: id, what: "redo restores the accepted rows")

    // A picker completion arriving after remap cannot edit the replacement raw slot.
    var voiceRequests: [Int] = []
    h.onChangeTrackVoiceRequested = { voiceRequests.append($0) }
    let voice = fx.point(.voice)
    _ = h.doublePointer(x: voice.x, y: voice.y, button: 1, modifiers: 0)
    report.expectEqual(expected: [0], actual: voiceRequests, cppID: id, what: "voice double click requests picker")
    report.expect(fx.document.moveTrack(0, to: 1), cppID: id, message: "picker target remaps")
    let remapped = HeaderDocumentBaseline(fx.document)
    h.completeVoiceRequest(program: 127)
    remapped.expectUnchanged(report, fx.document, cppID: id, phase: "stale voice completion")
}
