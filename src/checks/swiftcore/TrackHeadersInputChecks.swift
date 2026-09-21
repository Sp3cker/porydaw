import Foundation
import PorydawApp
import PorydawCore

// Presenter-level counterparts of trackheaderinput, trackheadermutations,
// trackheadermenu, and the non-pixel contracts in trackheaderraster/activitymeter.
// Window focus, tooltip absence, and actual pixels belong to the Quick checks.
private enum HeaderProbe { case title, voice, mute, solo, add }

@MainActor
private extension TrackHeadersFixture {
    func point(_ probe: HeaderProbe, row: Int = 0) -> (x: Double, y: Double) {
        let offset = Double(row * headers.rowHeight) - headers.scrollY
        if probe == .add {
            return (headers.trackHeaderWidth / 2, offset + Double(headers.rowHeight) / 2)
        }
        let rect = switch probe {
        case .title: headers.rows[row].titleRect
        case .voice: headers.rows[row].subtitleRect
        case .mute: headers.muteButtonRect
        case .solo: headers.soloButtonRect
        case .add: headers.renameEditorRect
        }
        return ((rect["x"] as? Double ?? 0) + (rect["width"] as? Double ?? 0) / 2,
                offset + (rect["y"] as? Double ?? 0) + (rect["height"] as? Double ?? 0) / 2)
    }

    func click(_ report: CheckReport, _ probe: HeaderProbe, row: Int = 0,
               cppID: String, modifiers: Int = 0) {
        let p = point(probe, row: row)
        report.expect(headers.beginPointer(x: p.x, y: p.y, button: 1, modifiers: modifiers),
                      cppID: cppID, message: "\(probe) row \(row) accepts press")
        report.expect(headers.endPointer(x: p.x, y: p.y, button: 1, modifiers: modifiers),
                      cppID: cppID, message: "\(probe) row \(row) accepts release")
    }

    func openMenu(_ report: CheckReport, track: Int = 0, cppID: String) {
        let p = point(.title, row: track)
        report.expect(headers.beginPointer(x: p.x, y: p.y, button: 2, modifiers: 0),
                      cppID: cppID, message: "right press is handled")
        report.expect(headers.menuOpen, cppID: cppID, message: "right press opens header menu")
    }

    func rebuild() {
        headers.detach()
        headers.attach(session: session, palette: GridPalette())
        headers.configureViewport(width: 228, height: 240, fontPx: 13, dpr: 1)
        headers.configureTextMetrics(titleLineSpacing: 18, boldLineSpacing: 18,
                                     subtitleLineSpacing: 16)
    }
}

@MainActor
private struct HeaderDocumentBaseline {
    let state: SongState
    let revision: UInt64
    let history: DocumentIdentity

    init(_ document: SongDocument) {
        state = document.state
        revision = document.revision
        history = document.history.currentIdentity
    }

    func expectUnchanged(_ report: CheckReport, _ document: SongDocument,
                         cppID: String, phase: String) {
        report.expectEqual(state, document.state, cppID: cppID, what: "\(phase): song unchanged")
        report.expectEqual(revision, document.revision, cppID: cppID,
                           what: "\(phase): no document write")
        report.expectEqual(history, document.history.currentIdentity, cppID: cppID,
                           what: "\(phase): history unchanged")
    }
}

@MainActor
internal func runTrackHeadersInputChecks(_ report: CheckReport, session: DocumentSession,
                                        service: ProjectService) {
    selectionAndVoiceRouteThroughHeaders(report, suite: session, service: service)
    muteAndSoloHonorCancellationAndButtons(report, suite: session, service: service)
    scrollClampsAndRoutesKeyboardAndWheelInput(report, suite: session, service: service)
    emptyTrackHeadersRejectInputWithoutMutation(report, suite: session, service: service)
    renameCommitsAndRebuildsHeader(report, suite: session, service: service)
    reorderCommitsAndRebuildsHeader(report, suite: session, service: service)
    addTrackOpensPickerAndRebuildsHeader(report, suite: session, service: service)
    headerMenuOpensWithTypedRowsAndDismissesWithoutWrite(report, suite: session, service: service)
    headerMenuChangeVoiceOpensPickerAfterMenuCloses(report, suite: session, service: service)
    headerMenuRenameBeginsAfterCloseAndFocusesEditor(report, suite: session, service: service)
    headerMenuRowsDispatchRevealDuplicateDelete(report, suite: session, service: service)
    headerMenuStaleStructuralChangeCancelsWithoutWrite(report, suite: session, service: service)
    headerMenuQueuedDestructiveMutationsDropAfterRemap(report, suite: session, service: service)
    headerMenuOutsidePressDismissesWithoutClickThrough(report, suite: session, service: service)
    voiceSubtitleFollowsProgramPosition(report, suite: session, service: service)
    activityRemainsSilentAndRebuiltTracksRetainIdentity(report, suite: session, service: service)
}

@MainActor
private func selectionAndVoiceRouteThroughHeaders(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::selectionAndVoiceRouteThroughHeaders"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let baseline = HeaderDocumentBaseline(fx.document)
    var revealed: [Int] = []
    h.onRevealTrackVoiceRequested = { revealed.append($0) }
    let unselected = h.rows[1].baseColor
    fx.click(report, .title, row: 1, cppID: id)
    report.expectEqual(1, fx.session.selectedTrack, cppID: id, what: "title selects primary track")
    report.expect(h.rows[1].baseColor != unselected && h.rows[1].titleBold,
                  cppID: id, message: "selection changes the visible title and base color")
    report.expect(!h.rows[0].titleBold, cppID: id, message: "old primary loses bold title")
    report.expectEqual([1], revealed, cppID: id, what: "title click reveals its voice once")

    let voice = fx.point(.voice)
    report.expect(h.beginPointer(x: voice.x, y: voice.y, button: 1, modifiers: 0),
                  cppID: id, message: "voice line accepts press")
    report.expectEqual(0, fx.session.selectedTrack, cppID: id,
                       what: "voice line selects at press, before release")
    report.expect(h.endPointer(x: voice.x, y: voice.y, button: 1, modifiers: 0),
                  cppID: id, message: "voice line accepts release")
    report.expectEqual([1, 0], revealed, cppID: id, what: "voice click reveals its own track")

    _ = h.beginPointer(x: voice.x, y: voice.y, button: 1, modifiers: 0)
    _ = h.updatePointer(x: voice.x, y: 0, modifiers: 0)
    report.expect(h.reorderIndicatorVisible, cppID: id,
                  message: "voice-line drag becomes a reorder gesture")
    _ = h.endPointer(x: voice.x, y: 0, button: 2, modifiers: 0)
    report.expect(!h.endPointer(x: voice.x, y: 0, button: 1, modifiers: 0),
                  cppID: id, message: "wrong-button cancellation consumes the armed drag")
    report.expect(!h.reorderIndicatorVisible, cppID: id, message: "cancel removes reorder marker")
    report.expectEqual([1, 0], revealed, cppID: id, what: "drag release never reveals a voice")
    let scoped = fx.point(.title, row: 1)
    _ = h.beginPointer(x: scoped.x, y: scoped.y, button: 1, modifiers: 0x0400_0000)
    _ = h.endPointer(x: scoped.x, y: scoped.y, button: 1, modifiers: 0x0400_0000)
    report.expectEqual([1, 0], revealed, cppID: id, what: "modified selection never reveals a voice")
    // DocumentSession has no stored multi-track scope yet; do not fabricate a mask.
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "header selection and reveals")
}

@MainActor
private func muteAndSoloHonorCancellationAndButtons(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::muteAndSoloHonorCancellationAndButtons"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    fx.session.selectedTrack = 1
    h.refreshFromDocument()
    let baseline = HeaderDocumentBaseline(fx.document)
    let rebuilds = h.rowRebuildCount
    let unaffected = h.rows[1]
    let mute = fx.point(.mute)
    let title = fx.point(.title)
    h.updateHover(x: mute.x, y: mute.y)
    report.expect(h.rows[0].muteHovered, cppID: id, message: "mute hover is visible")
    h.clearHover()
    report.expect(!h.rows[0].muteHovered, cppID: id, message: "pointer leave clears mute hover")
    _ = h.beginPointer(x: mute.x, y: mute.y, button: 1, modifiers: 0)
    report.expect(h.rows[0].mutePressed, cppID: id, message: "left press depresses mute")
    _ = h.beginPointer(x: title.x, y: title.y, button: 2, modifiers: 0)
    report.expect(h.rows[0].mutePressed && !h.menuOpen, cppID: id,
                  message: "additional right press does not replace held mute")
    _ = h.endPointer(x: title.x, y: title.y, button: 2, modifiers: 0)
    report.expect(!h.rows[0].mutePressed && !h.rows[0].muteChecked, cppID: id,
                  message: "wrong-button release cancels mute without toggling")

    // GridCancelReason raw values: FocusLost, PointerUngrabbed, Hidden, WindowDeactivated.
    for reason in 0...3 {
        _ = h.beginPointer(x: mute.x, y: mute.y, button: 1, modifiers: 0)
        h.inputCancelled(reason: reason)
        report.expect(!h.rows[0].mutePressed && !h.rows[0].muteChecked,
                      cppID: id, message: "cancel reason \(reason) releases mute without toggling")
        report.expect(!h.endPointer(x: mute.x, y: mute.y, button: 1, modifiers: 0),
                      cppID: id, message: "cancel reason \(reason) rejects late release")
    }
    fx.click(report, .mute, cppID: id)
    report.expect(fx.session.mutedTracks.contains(0) && h.rows[0].muteChecked,
                  cppID: id, message: "mute click changes session mask and visible checked state")
    h.activateMute(track: 0)
    report.expect(!fx.session.mutedTracks.contains(0) && !h.rows[0].muteChecked,
                  cppID: id, message: "keyboard mute activation clears the same toggle")
    let solo = fx.point(.solo)
    h.updateHover(x: solo.x, y: solo.y)
    report.expect(h.rows[0].soloHovered, cppID: id, message: "solo hover is visible")
    h.clearHover()
    report.expect(!h.rows[0].soloHovered, cppID: id, message: "pointer leave clears solo hover")
    _ = h.beginPointer(x: solo.x, y: solo.y, button: 1, modifiers: 0)
    report.expect(h.rows[0].soloPressed, cppID: id, message: "solo press is visible")
    _ = h.endPointer(x: solo.x, y: solo.y, button: 1, modifiers: 0)
    report.expect(fx.session.soloedTracks.contains(0) && h.rows[0].soloChecked,
                  cppID: id, message: "solo click changes session mask and visible checked state")
    h.activateSolo(track: 0)
    report.expect(!fx.session.soloedTracks.contains(0) && !h.rows[0].soloChecked,
                  cppID: id, message: "keyboard solo activation clears the same toggle")
    fx.session.mutedTracks = [0]
    h.refreshFromDocument()
    report.expect(h.rows[0].muteChecked, cppID: id, message: "external session mute reaches header")
    report.expect(h.rows[1] === unaffected, cppID: id, message: "mask changes retain unrelated row")
    report.expectEqual(rebuilds, h.rowRebuildCount, cppID: id, what: "toggles never rebuild rows")
    report.expectEqual(1, fx.session.selectedTrack, cppID: id, what: "toggles preserve primary track")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "session-only masks")
}

@MainActor
private func scrollClampsAndRoutesKeyboardAndWheelInput(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::scrollClampsAndRoutesKeyboardAndWheelInput"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    h.configureViewport(width: 228, height: Double(h.rowHeight), fontPx: 13, dpr: 1)
    let maximum = h.maximumScrollY
    report.expect(maximum > 0, cppID: id, message: "one-row viewport has a scroll range")
    h.scrollY = maximum + Double(h.rowHeight)
    report.expectEqual(maximum, h.scrollY, cppID: id, what: "scrollbar overshoot clamps at bottom")
    h.scrollY = -Double(h.rowHeight)
    report.expectEqual(0, h.scrollY, cppID: id, what: "scrollbar undershoot clamps at top")
    // TimelineScrollbar's Down key writes one row to this public scroll property.
    h.scrollY += Double(h.rowHeight)
    let afterKey = min(Double(h.rowHeight), maximum)
    report.expectEqual(afterKey, h.scrollY, cppID: id, what: "keyboard step scrolls one row")
    report.expect(!h.handleWheel(angleDeltaX: 120, angleDeltaY: 0, pixelDeltaX: 0,
                                pixelDeltaY: 0, modifiers: 0, phase: 0),
                  cppID: id, message: "horizontal wheel is rejected")
    report.expectEqual(afterKey, h.scrollY, cppID: id, what: "horizontal wheel leaves scroll alone")
    h.scrollY = 0
    report.expect(h.handleWheel(angleDeltaX: 0, angleDeltaY: -120, pixelDeltaX: 0,
                               pixelDeltaY: 0, modifiers: 0, phase: 0),
                  cppID: id, message: "vertical wheel is accepted")
    report.expectEqual(afterKey, h.scrollY, cppID: id, what: "one wheel notch scrolls one row")
    _ = h.handleWheel(angleDeltaX: 0, angleDeltaY: -120, pixelDeltaX: 0,
                      pixelDeltaY: 7, modifiers: 0, phase: 0)
    report.expectEqual(afterKey - 7, h.scrollY, cppID: id,
                       what: "trackpad pixel delta takes precedence over angle delta")
}

@MainActor
private func emptyTrackHeadersRejectInputWithoutMutation(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::emptyTrackHeadersRejectInputWithoutMutation"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let initial = HeaderDocumentBaseline(fx.document)
    report.expect(!fx.headers.beginPointer(x: -1, y: -1, button: 1, modifiers: 0),
                  cppID: id, message: "negative header coordinates are rejected")
    initial.expectUnchanged(report, fx.document, cppID: id, phase: "outside press")
    fx.document.deleteTrack(1)
    fx.document.deleteTrack(0)
    let empty = HeaderDocumentBaseline(fx.document)
    report.expectEqual(0, fx.headers.rows.count, cppID: id, what: "empty song publishes zero rows")
    report.expect(!fx.headers.beginPointer(x: 1, y: 1, button: 1, modifiers: 0),
                  cppID: id, message: "empty header rejects press")
    report.expect(!fx.headers.endPointer(x: 1, y: 1, button: 1, modifiers: 0),
                  cppID: id, message: "empty header rejects release")
    fx.headers.activateMute(track: 0)
    fx.headers.activateSolo(track: 0)
    fx.headers.activateAddTrack()
    fx.headers.completeVoiceRequest(program: 127)
    empty.expectUnchanged(report, fx.document, cppID: id, phase: "empty input")
}

@MainActor
private func renameCommitsAndRebuildsHeader(
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
private func reorderCommitsAndRebuildsHeader(
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
private func addTrackOpensPickerAndRebuildsHeader(
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

@MainActor
private func headerMenuOpensWithTypedRowsAndDismissesWithoutWrite(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuOpensWithTypedRowsAndDismissesWithoutWrite"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    fx.session.selectedTrack = 1
    let baseline = HeaderDocumentBaseline(fx.document)
    fx.openMenu(report, cppID: id)
    report.expectEqual(0, fx.session.selectedTrack, cppID: id, what: "right press selects target")
    report.expectEqual([1, 2, 3, 4, 5], (0..<h.menuItems.count).map { h.menuItems[$0].actionId },
                       cppID: id, what: "menu exposes all five typed actions in order")
    report.expect((0..<h.menuItems.count).allSatisfy { h.menuItems[$0].enabled },
                  cppID: id, message: "all actions are available below capacity")
    h.dismissHeaderMenu()
    report.expect(!h.menuOpen, cppID: id, message: "dismiss closes menu")
    report.expectEqual(0, fx.session.selectedTrack, cppID: id, what: "dismiss retains selected target")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "menu open and dismiss")
    while fx.document.canAddTrack {
        guard fx.document.duplicateTrack(0) != nil else {
            report.fail(id, "could not fill engine track capacity")
            return
        }
    }
    report.expectEqual(16, fx.document.engineTracks.usedTrackCount, cppID: id,
                       what: "fixture reaches sixteen-track capacity")
    report.expectEqual(16, h.rows.count, cppID: id, what: "capacity removes add row")
    fx.openMenu(report, cppID: id)
    report.expectEqual([4], (0..<h.menuItems.count).filter { !h.menuItems[$0].enabled }
        .map { h.menuItems[$0].actionId }, cppID: id, what: "only duplicate is disabled at capacity")
    let full = HeaderDocumentBaseline(fx.document)
    h.activateHeaderMenuAction(actionId: 4)
    report.expect(h.menuOpen, cppID: id, message: "disabled duplicate neither dispatches nor dismisses")
    full.expectUnchanged(report, fx.document, cppID: id, phase: "disabled duplicate")
    h.dismissHeaderMenu()
}

@MainActor
private func headerMenuChangeVoiceOpensPickerAfterMenuCloses(
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
    h.activateHeaderMenuAction(actionId: 1)
    report.expectEqual([1], requests, cppID: id, what: "change voice requests selected track picker")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "change voice requested")
    h.completeVoiceRequest(program: -1)
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "change voice cancelled")
    fx.openMenu(report, track: 1, cppID: id)
    h.activateHeaderMenuAction(actionId: 1)
    h.completeVoiceRequest(program: 127)
    report.expectEqual([127], fx.document.lanePoints(track: 1, lane: .voice).map(\.value),
                       cppID: id, what: "accepted picker edits captured track program")
    report.expectEqual([0], fx.document.lanePoints(track: 0, lane: .voice).map(\.value),
                       cppID: id, what: "voice edit leaves other track untouched")
    report.expectEqual(baseline.revision + 1, fx.document.revision, cppID: id,
                       what: "voice acceptance creates one edit")
}

@MainActor
private func headerMenuRenameBeginsAfterCloseAndFocusesEditor(
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
    report.expectEqual("Lead", h.renameDraft, cppID: id, what: "editor starts with editable track name")
    h.renameDraft = "Discard menu rename"
    h.finishRename(commit: false, restoreRollFocus: true)
    h.finishRename(commit: true, restoreRollFocus: false)
    report.expectEqual(-1, h.renamingTrack, cppID: id, what: "cancelled editor cannot reopen or commit")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "menu rename cancelled")
}

@MainActor
private func headerMenuRowsDispatchRevealDuplicateDelete(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerMenuRowsDispatchRevealDuplicateDelete"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let baseline = HeaderDocumentBaseline(fx.document)
    var reveals: [Int] = []
    h.onRevealTrackVoiceRequested = { [weak h] track in
        report.expect(h?.menuOpen == false, cppID: id, message: "menu closes before reveal")
        reveals.append(track)
    }
    fx.openMenu(report, track: 1, cppID: id)
    h.activateHeaderMenuAction(actionId: 2)
    report.expectEqual([1], reveals, cppID: id, what: "reveal addresses requested track")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "menu reveal")
    let notes = fx.document.notes(in: 0).map { "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)" }
    fx.openMenu(report, cppID: id)
    h.activateHeaderMenuAction(actionId: 4)
    report.expect(!h.menuOpen, cppID: id, message: "duplicate closes menu")
    report.expectEqual(3, fx.trackRows.count, cppID: id, what: "duplicate adds one track")
    report.expectEqual(notes, fx.document.notes(in: 2).map {
        "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)"
    }, cppID: id, what: "duplicate copies content rather than creating an empty slot")
    report.expectEqual(baseline.revision + 1, fx.document.revision, cppID: id,
                       what: "duplicate is one edit")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "duplicate undo succeeds")
    report.expectEqual(baseline.state, fx.document.state, cppID: id, what: "one undo removes duplicate")
    let beforeDelete = fx.document.revision
    fx.openMenu(report, track: 1, cppID: id)
    h.activateHeaderMenuAction(actionId: 5)
    report.expect(!h.menuOpen, cppID: id, message: "delete closes menu")
    fx.expectRows(report, names: ["Lead"], cppID: id, phase: "menu deletion")
    report.expectEqual(beforeDelete + 1, fx.document.revision, cppID: id, what: "delete is one edit")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "delete undo succeeds")
    report.expectEqual(baseline.state, fx.document.state, cppID: id, what: "undo restores deleted music")
    fx.expectRows(report, names: ["Lead", "Bass"], cppID: id, phase: "delete undo")
}

@MainActor
private func headerMenuStaleStructuralChangeCancelsWithoutWrite(
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
    report.expectEqual(0, pickers, cppID: id, what: "late stale action cannot open picker")
    remapped.expectUnchanged(report, fx.document, cppID: id, phase: "stale menu action")
    fx.openMenu(report, cppID: id)
    report.expectEqual(5, h.menuItems.count, cppID: id, what: "fresh menu remains usable after remap")
    h.dismissHeaderMenu()
}

@MainActor
private func headerMenuQueuedDestructiveMutationsDropAfterRemap(
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
private func headerMenuOutsidePressDismissesWithoutClickThrough(
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
        report.expectEqual(0, fx.session.selectedTrack, cppID: id,
                           what: "outside button \(button) never clicks through to selection")
        report.expectEqual(0, reveals, cppID: id, what: "outside button \(button) never reveals a voice")
        baseline.expectUnchanged(report, fx.document, cppID: id, phase: "outside button \(button)")
    }
}

@MainActor
private func voiceSubtitleFollowsProgramPosition(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::voiceSubtitleFollowsProgramPosition"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    fx.document.writeLane(track: 1, lane: .voice, from: 480, through: 480,
                          points: [LaneWrite(tick: 480, value: 5)])
    let baseline = HeaderDocumentBaseline(fx.document)
    let initial = h.rows[1].subtitle
    let unaffected = h.rows[0]
    let rebuilds = h.rowRebuildCount
    fx.session.editCursor = 479
    h.refreshFromDocument()
    report.expectEqual(initial, h.rows[1].subtitle, cppID: id,
                       what: "cursor before change still shows first program")
    fx.session.editCursor = 480
    h.refreshFromDocument()
    let changed = h.rows[1].subtitle
    report.expect(changed != initial, cppID: id, message: "cursor at change publishes new subtitle")
    report.expect(h.rows[0] === unaffected, cppID: id, message: "program transition retains unrelated row")
    fx.session.editCursor = 0
    h.refreshFromDocument()
    report.expectEqual(initial, h.rows[1].subtitle, cppID: id, what: "stopped cursor restores first program")
    h.refreshPlayhead(tick: 480, playing: true)
    report.expectEqual(changed, h.rows[1].subtitle, cppID: id, what: "playing follows playhead over edit cursor")
    let retained = h.rows[1]
    h.refreshPlayhead(tick: 481, playing: true)
    report.expect(h.rows[1] === retained, cppID: id, message: "unchanged program retains published row")
    h.refreshPlayhead(tick: 481, playing: false)
    report.expectEqual(initial, h.rows[1].subtitle, cppID: id, what: "stop immediately returns to edit cursor")
    report.expectEqual(rebuilds, h.rowRebuildCount, cppID: id, what: "subtitle transitions never rebuild rows")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "cursor and playhead changes")
}

@MainActor
private func activityRemainsSilentAndRebuiltTracksRetainIdentity(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    // NativeAudio has no per-track activity feed. Skip live activity-pixel heights,
    // physical-pixel boundaries and intensity caps; never inject fake meter levels.
    // Preserve the observable silence, unchanged-publication and rebuild policies.
    let silenceID = "swiftcore/TrackHeaders::activityRasterMatchesRolesAndIsSilentWhenUnchanged"
    let scopeID = "swiftcore/TrackHeaders::roleScopedUpdatesAndPhysicalPixelBoundaries"
    let pauseID = "swiftcore/TrackHeaders::pauseRasterAndIntensityCapUseObservedDpr"
    let identityID = "swiftcore/TrackHeaders::stereoRasterAndRebuiltTracksRetainIdentity"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let retained = fx.trackRows
    let rebuilds = h.rowRebuildCount
    for playing in [false, true, false] {
        h.refreshPlayhead(tick: 24, playing: playing)
        h.refreshFromDocument()
        for (index, row) in fx.trackRows.enumerated() {
            report.expectEqual(0, row.activityLeftHeight, cppID: silenceID,
                               what: "playing \(playing), track \(index): absent left feed stays silent")
            report.expectEqual(0, row.activityRightHeight, cppID: pauseID,
                               what: "playing \(playing), track \(index): absent right feed stays silent")
            report.expect(row === retained[index], cppID: scopeID,
                          message: "playing \(playing), track \(index): unchanged silence publishes no new row")
        }
    }
    report.expectEqual(rebuilds, h.rowRebuildCount, cppID: silenceID,
                       what: "unchanged activity does not reset model")
    let colors = fx.trackRows.map(\.activityActiveColor)
    report.expect(colors[0] != colors[1], cppID: identityID,
                  message: "distinct engine tracks have distinct meter identities")
    fx.rebuild()
    report.expectEqual(colors, fx.trackRows.map(\.activityActiveColor), cppID: identityID,
                       what: "rebuild restores the same per-track meter colors")
    report.expect(fx.document.duplicateTrack(0) != nil, cppID: identityID,
                  message: "structural edit adds another track identity")
    report.expectEqual([0, 1, 2], fx.trackRows.map(\.track), cppID: identityID,
                       what: "rebuilt meter rows address each current engine track exactly once")
    report.expectEqual(colors, Array(fx.trackRows.prefix(2)).map(\.activityActiveColor),
                       cppID: identityID, what: "existing track identities survive structural rebuild")
    for row in fx.trackRows {
        report.expect(row.activityLeftHeight == 0 && row.activityRightHeight == 0,
                      cppID: identityID, message: "rebuilt track \(row.track) inherits no stale activity")
    }
    let afterRebuild = fx.trackRows
    let afterCount = h.rowRebuildCount
    h.refreshFromDocument()
    report.expectEqual(afterCount, h.rowRebuildCount, cppID: identityID,
                       what: "unchanged rebuilt model remains quiet")
    report.expect(zip(afterRebuild, fx.trackRows).allSatisfy { pair in pair.0 === pair.1 }, cppID: identityID,
                  message: "unchanged rebuilt rows retain their published identities")
}
