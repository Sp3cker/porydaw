import Foundation
import PorydawApp
import PorydawCore

@MainActor
func headerMenuOpensWithTypedRowsAndDismissesWithoutWrite(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuOpensWithTypedRowsAndDismissesWithoutWrite"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    fx.session.selectedTrack = 1
    let baseline = HeaderDocumentBaseline(fx.document)
    fx.openMenu(report, cppID: id)
    report.expectEqual(expected: 0, actual: fx.session.selectedTrack, cppID: id, what: "right press selects target")
    report.expectEqual(expected: [1, 2, 3, 4, 5], actual: (0..<h.menuItems.count).map { h.menuItems[$0].actionId },
                       cppID: id, what: "menu exposes all five typed actions in order")
    report.expect((0..<h.menuItems.count).allSatisfy { h.menuItems[$0].enabled },
                  cppID: id, message: "all actions are available below capacity")
    h.dismissHeaderMenu()
    report.expect(!h.menuOpen, cppID: id, message: "dismiss closes menu")
    report.expectEqual(expected: 0, actual: fx.session.selectedTrack, cppID: id, what: "dismiss retains selected target")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "menu open and dismiss")
    while fx.document.canAddTrack {
        guard fx.document.duplicateTrack(0) != nil else {
            report.fail(id, "could not fill engine track capacity")
            return
        }
    }
    report.expectEqual(expected: 16, actual: fx.document.engineTracks.usedTrackCount, cppID: id,
                       what: "fixture reaches sixteen-track capacity")
    report.expectEqual(expected: 16, actual: h.rows.count, cppID: id, what: "capacity removes add row")
    fx.openMenu(report, cppID: id)
    report.expectEqual(expected: [4], actual: (0..<h.menuItems.count).filter { !h.menuItems[$0].enabled }
        .map { h.menuItems[$0].actionId }, cppID: id, what: "only duplicate is disabled at capacity")
    let full = HeaderDocumentBaseline(fx.document)
    h.activateHeaderMenuAction(actionId: 4)
    report.expect(h.menuOpen, cppID: id, message: "disabled duplicate neither dispatches nor dismisses")
    full.expectUnchanged(report, fx.document, cppID: id, phase: "disabled duplicate")
    h.dismissHeaderMenu()
    report.expect(!h.menuOpen, cppID: id, message: "dismiss closes the capacity menu")
}

@MainActor
func headerMenuTargetRowResolvesByTrack(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuTargetRowResolvesByTrack"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let target = 1
    let baseline = HeaderDocumentBaseline(fx.document)
    guard let row = fx.rowForTrack(target) else {
        report.fail(id, "target track has no header row")
        return
    }
    report.expect(row != 0 && h.rows[row].track == target, cppID: id,
                  message: "non-leading header row resolves from track identity")
    guard let p = fx.visibleTitlePoint(forTrack: target) else {
        report.fail(id, "target track has no visible title point")
        return
    }
    var revealed: [Int] = []
    h.onRevealTrackVoiceRequested = { revealed.append($0) }
    report.expect(h.beginPointer(x: p.x, y: p.y, button: 2, modifiers: 0),
                  cppID: id, message: "identity-resolved row accepts right press")
    report.expect(h.menuOpen, cppID: id, message: "identity-resolved header opens menu")
    report.expectEqual(expected: target, actual: fx.session.selectedTrack, cppID: id,
                       what: "right press selects identity-resolved target")
    h.activateHeaderMenuAction(actionId: 2)
    report.expectEqual(expected: [target], actual: revealed, cppID: id,
                       what: "menu target resolves to identity-resolved track")
    report.expect(!h.menuOpen, cppID: id, message: "menu action closes first menu")
    report.expect(h.beginPointer(x: p.x, y: p.y, button: 2, modifiers: 0),
                  cppID: id, message: "same target reopens for dismissal")
    h.dismissHeaderMenu()
    report.expect(!h.menuOpen, cppID: id, message: "dismiss closes target menu")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "identity menu open and dismiss")
}

@MainActor
func headerMenuChangeVoiceOpensPickerAfterMenuCloses(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuChangeVoiceOpensPickerAfterMenuCloses"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let baseline = HeaderDocumentBaseline(fx.document)
    var requests: [Int] = []
    h.onChangeTrackVoiceRequested = { [weak h] track in
        report.expect(h?.menuOpen == false, cppID: id, message: "menu closes before picker request")
        requests.append(track)
    }
    fx.openMenu(report, track: 1, cppID: id)
    report.expectEqual(expected: 1, actual: fx.session.selectedTrack, cppID: id,
                       what: "right press selects the voice track")
    h.activateHeaderMenuAction(actionId: 1)
    report.expectEqual(expected: [1], actual: requests, cppID: id, what: "change voice requests selected track picker")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "change voice requested")
    h.completeVoiceRequest(program: -1)
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "change voice cancelled")
    report.expectEqual(expected: 1, actual: fx.session.selectedTrack, cppID: id,
                       what: "cancelled picker retains the voice track selection")
    fx.openMenu(report, track: 1, cppID: id)
    h.activateHeaderMenuAction(actionId: 1)
    h.completeVoiceRequest(program: 127)
    report.expectEqual(expected: [127], actual: fx.document.lanePoints(track: 1, lane: .voice).map(\.value),
                       cppID: id, what: "accepted picker edits captured track program")
    report.expectEqual(expected: [0], actual: fx.document.lanePoints(track: 0, lane: .voice).map(\.value),
                       cppID: id, what: "voice edit leaves other track untouched")
    report.expectEqual(expected: baseline.revision + 1, actual: fx.document.revision, cppID: id,
                       what: "voice acceptance creates one edit")
}

@MainActor
func headerMenuRenameBeginsAfterCloseAndFocusesEditor(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuRenameBeginsAfterCloseAndFocusesEditor"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let baseline = HeaderDocumentBaseline(fx.document)
    fx.openMenu(report, cppID: id)
    h.activateHeaderMenuAction(actionId: 3)
    report.expect(!h.menuOpen && h.renamingTrack == 0, cppID: id,
                  message: "rename editor replaces closed menu synchronously")
    report.expectEqual(expected: "Lead", actual: h.renameDraft, cppID: id, what: "editor starts with editable track name")
    h.renameDraft = "Discard menu rename"
    h.finishRename(commit: false, restoreRollFocus: true)
    h.finishRename(commit: true, restoreRollFocus: false)
    report.expectEqual(expected: -1, actual: h.renamingTrack, cppID: id, what: "cancelled editor cannot reopen or commit")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "menu rename cancelled")
}

@MainActor
func headerMenuRowsDispatchRevealDuplicateDelete(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuRowsDispatchRevealDuplicateDelete"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    fx.document.writeLane(track: 1, lane: .voice, from: 0, through: 0,
                          points: [LaneWrite(tick: 0, value: 42)])
    let baseline = HeaderDocumentBaseline(fx.document)
    var reveals: [Int] = []
    var revealedPrograms: [Int] = []
    h.onRevealTrackVoiceRequested = { [weak h, session = fx.session, document = fx.document] track in
        report.expect(h?.menuOpen == false, cppID: id, message: "menu closes before reveal")
        reveals.append(track)
        revealedPrograms.append(VoiceLanePolicy.slot(
            firstProgram: session.timeline.tracks[track].firstProgram,
            tick: session.editCursor, points: document.lanePoints(track: track, lane: .voice)))
    }
    fx.openMenu(report, track: 1, cppID: id)
    h.activateHeaderMenuAction(actionId: 2)
    report.expectEqual(expected: [1], actual: reveals, cppID: id, what: "reveal addresses requested track")
    report.expectEqual(expected: [42], actual: revealedPrograms, cppID: id,
                       what: "track-addressed menu request resolves to current voice program")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "menu reveal")
    let notes = fx.document.notes(in: 0).map { "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)" }
    report.expect(!notes.isEmpty, cppID: id,
                  message: "the duplicate fixture track carries content to copy")
    fx.openMenu(report, cppID: id)
    h.activateHeaderMenuAction(actionId: 4)
    report.expect(!h.menuOpen, cppID: id, message: "duplicate closes menu")
    report.expectEqual(expected: 3, actual: fx.trackRows.count, cppID: id, what: "duplicate adds one track")
    report.expectEqual(expected: notes, actual: fx.document.notes(in: 2).map {
        "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)"
    }, cppID: id, what: "duplicate copies content rather than creating an empty slot")
    report.expectEqual(expected: baseline.revision + 1, actual: fx.document.revision, cppID: id,
                       what: "duplicate is one edit")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "duplicate undo succeeds")
    report.expectEqual(expected: baseline.state, actual: fx.document.state, cppID: id, what: "one undo removes duplicate")
    let beforeDelete = fx.document.revision
    fx.openMenu(report, track: 1, cppID: id)
    h.activateHeaderMenuAction(actionId: 5)
    report.expect(!h.menuOpen, cppID: id, message: "delete closes menu")
    fx.expectRows(report, names: ["Lead"], cppID: id, phase: "menu deletion")
    report.expectEqual(expected: beforeDelete + 1, actual: fx.document.revision, cppID: id, what: "delete is one edit")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "delete undo succeeds")
    report.expectEqual(expected: baseline.state, actual: fx.document.state, cppID: id, what: "undo restores deleted music")
    fx.expectRows(report, names: ["Lead", "Bass"], cppID: id, phase: "delete undo")
}

@MainActor
func headerMenuStaleStructuralChangeCancelsWithoutWrite(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuStaleStructuralChangeCancelsWithoutWrite"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    var pickers = 0
    h.onChangeTrackVoiceRequested = { _ in pickers += 1 }
    fx.openMenu(report, track: 1, cppID: id)
    report.expect(fx.document.moveTrack(0, to: 1), cppID: id, message: "open menu target remaps")
    let remapped = HeaderDocumentBaseline(fx.document)
    report.expect(!h.menuOpen && h.renamingTrack == -1, cppID: id,
                  message: "structural remap cancels menu without starting editor")
    h.activateHeaderMenuAction(actionId: 1)
    h.completeVoiceRequest(program: 127)
    report.expectEqual(expected: 0, actual: pickers, cppID: id, what: "late stale action cannot open picker")
    remapped.expectUnchanged(report, fx.document, cppID: id, phase: "stale menu action")
    fx.openMenu(report, cppID: id)
    report.expectEqual(expected: 5, actual: h.menuItems.count, cppID: id, what: "fresh menu remains usable after remap")
    h.dismissHeaderMenu()
}

@MainActor
func headerMenuQueuedDestructiveMutationsDropAfterRemap(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuQueuedDestructiveMutationsDropAfterRemap"
    for action in [5, 4] {
        let fx = TrackHeadersFixture(suite: suite, service: service)
        let h = fx.headers
        fx.openMenu(report, track: 1, cppID: id)
        // Deliver the captured menu action after another event remaps its raw slot.
        report.expect(fx.document.moveTrack(1, to: 0), cppID: id,
                      message: "action \(action): remap precedes delayed activation")
        let remapped = HeaderDocumentBaseline(fx.document)
        h.activateHeaderMenuAction(actionId: action)
        remapped.expectUnchanged(report, fx.document, cppID: id, phase: "delayed action \(action)")
        report.expect(!h.menuOpen, cppID: id, message: "action \(action): stale menu stays closed")
        fx.expectRows(report, names: ["Bass", "Lead"], cppID: id, phase: "delayed action \(action)")
    }
}

@MainActor
func headerMenuOutsidePressDismissesWithoutClickThrough(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuOutsidePressDismissesWithoutClickThrough"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let baseline = HeaderDocumentBaseline(fx.document)
    var reveals = 0
    h.onRevealTrackVoiceRequested = { _ in reveals += 1 }
    let outside = fx.point(.title, row: 1)
    for button in [1, 2] {
        fx.openMenu(report, cppID: id)
        _ = h.beginPointer(x: outside.x, y: outside.y, button: button, modifiers: 0)
        _ = h.endPointer(x: outside.x, y: outside.y, button: button, modifiers: 0)
        report.expect(!h.menuOpen, cppID: id, message: "outside button \(button) dismisses without reopening")
        report.expectEqual(expected: 0, actual: fx.session.selectedTrack, cppID: id,
                           what: "outside button \(button) never clicks through to selection")
        report.expectEqual(expected: 0, actual: reveals, cppID: id, what: "outside button \(button) never reveals a voice")
        baseline.expectUnchanged(report, fx.document, cppID: id, phase: "outside button \(button)")
    }
}
