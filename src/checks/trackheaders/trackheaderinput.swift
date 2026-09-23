import Foundation
import PorydawApp
import PorydawCore

@MainActor
func selectionAndVoiceRouteThroughHeaders(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::selectionAndVoiceRouteThroughHeaders"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    fx.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                          points: [LaneWrite(tick: 0, value: 17)])
    fx.document.writeLane(track: 1, lane: .voice, from: 0, through: 0,
                          points: [LaneWrite(tick: 0, value: 42)])
    let baseline = HeaderDocumentBaseline(fx.document)
    var revealed: [Int] = []
    var revealedPrograms: [Int] = []
    h.onRevealTrackVoiceRequested = { [session = fx.session, document = fx.document] track in
        revealed.append(track)
        revealedPrograms.append(VoiceLanePolicy.slot(
            firstProgram: session.timeline.tracks[track].firstProgram,
            tick: session.editCursor, points: document.lanePoints(track: track, lane: .voice)))
    }
    let unselected = h.rows[1].baseColor
    fx.click(report, .title, row: 1, cppID: id)
    report.expectEqual(1, fx.session.selectedTrack, cppID: id, what: "title selects primary track")
    report.expect(h.rows[1].baseColor != unselected && h.rows[1].titleBold,
                  cppID: id, message: "selection changes the visible title and base color")
    report.expect(!h.rows[0].titleBold, cppID: id, message: "old primary loses bold title")
    report.expectEqual([1], revealed, cppID: id, what: "title click reveals its voice once")
    report.expectEqual([42], revealedPrograms, cppID: id,
                       what: "track-addressed title request resolves to the current program, not track ID")

    let voice = fx.point(.voice)
    report.expect(h.beginPointer(x: voice.x, y: voice.y, button: 1, modifiers: 0),
                  cppID: id, message: "voice line accepts press")
    report.expectEqual(0, fx.session.selectedTrack, cppID: id,
                       what: "voice line selects at press, before release")
    report.expect(h.endPointer(x: voice.x, y: voice.y, button: 1, modifiers: 0),
                  cppID: id, message: "voice line accepts release")
    report.expectEqual([1, 0], revealed, cppID: id, what: "voice click reveals its own track")
    report.expectEqual([42, 17], revealedPrograms, cppID: id,
                       what: "voice-line request resolves the clicked track's current program")

    // The title line of the voice track behaves the same way.
    fx.click(report, .title, row: 0, cppID: id)
    report.expectEqual([1, 0, 0], revealed, cppID: id,
                       what: "voice-row title click reveals its own track")
    report.expectEqual(0, fx.session.selectedTrack, cppID: id,
                       what: "voice-row title click retains its selection")

    _ = h.beginPointer(x: voice.x, y: voice.y, button: 1, modifiers: 0)
    _ = h.updatePointer(x: voice.x, y: 0, modifiers: 0)
    report.expect(h.reorderIndicatorVisible, cppID: id,
                  message: "voice-line drag becomes a reorder gesture")
    report.expect(h.endPointer(x: voice.x, y: 0, button: 2, modifiers: 0),
                  cppID: id, message: "wrong-button release consumes the armed drag")
    report.expect(!h.endPointer(x: voice.x, y: 0, button: 1, modifiers: 0),
                  cppID: id, message: "cancelled drag leaves no pending release")
    report.expect(!h.reorderIndicatorVisible, cppID: id, message: "cancel removes reorder marker")
    report.expectEqual([1, 0, 0], revealed, cppID: id, what: "drag release never reveals a voice")
    let scoped = fx.point(.title, row: 1)
    let beforeScope = fx.session.selectedTracks
    _ = h.beginPointer(x: scoped.x, y: scoped.y, button: 1, modifiers: 0x0400_0000)
    _ = h.endPointer(x: scoped.x, y: scoped.y, button: 1, modifiers: 0x0400_0000)
    report.expectEqual([1, 0, 0], revealed, cppID: id, what: "modified selection never reveals a voice")
    report.expectEqual(beforeScope.symmetricDifference([1]), fx.session.selectedTracks,
                       cppID: id, what: "Ctrl-click toggles exactly the clicked track in scope")
    report.expectEqual(0, fx.session.selectedTrack, cppID: id,
                       what: "Ctrl-click of another track retains the primary")
    report.expect(h.rows[1].overlayColor != "#00000000", cppID: id,
                  message: "secondary scope renders the original selection overlay")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "header selection and reveals")
}

@MainActor
func headerSelectionTargetsResolve(
    _ report: CheckReport, suite: DocumentSession, service: ProjectService
) {
    let id = "swiftcore/TrackHeaders::headerSelectionTargetsResolve"
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let h = fx.headers
    let rows = (0..<h.rows.count).map { h.rows[$0] }
    let trackRows = rows.filter { !$0.isAddTrack }
    report.expectEqual(1, rows.count - trackRows.count, cppID: id,
                       what: "exactly one add row follows the tracks")
    report.expect(trackRows.allSatisfy { $0.track >= 0 }, cppID: id,
                  message: "every track row resolves an engine track")
    let selectedRow = trackRows.firstIndex { $0.titleBold }
    report.expect(selectedRow != nil, cppID: id,
                  message: "the session's selected track resolves to a row")
    let targetRow = selectedRow == 0 ? 1 : 0
    report.expect(targetRow < trackRows.count, cppID: id,
                  message: "an alternate row exists beside the selection")
    report.expect(trackRows[targetRow].track >= 0, cppID: id,
                  message: "the alternate row resolves an engine track")
    let titleRect = trackRows[targetRow].titleRect
    report.expect((titleRect["width"] as? Double ?? 0) > 0
                  && (titleRect["height"] as? Double ?? 0) > 0,
                  cppID: id, message: "title rect is populated")
    // Geometry stays populated after the band scrolls.
    h.scrollY += Double(h.rowHeight)
    let scrolledRect = trackRows[targetRow].titleRect
    report.expect((scrolledRect["width"] as? Double ?? 0) > 0
                  && (scrolledRect["height"] as? Double ?? 0) > 0,
                  cppID: id, message: "title rect stays populated after scroll")
}

@MainActor
func trackHeaderScopeTransitions(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService) {
    let fx = TrackHeadersFixture(suite: suite, service: service)
    let session = fx.session
    let id = "TrackHeadersTest::selectionAndVoiceRouteThroughHeaders"
    let baseline = HeaderDocumentBaseline(fx.document)
    session.adjustTrackScope(track: 1, action: .toggle)
    report.expectEqual(Set([0, 1]), session.selectedTracks, cppID: id, what: "Ctrl adds secondary scope")
    session.adjustTrackScope(track: 0, action: .toggle)
    report.expectEqual(1, session.selectedTrack, cppID: id, what: "removing primary chooses first surviving track")
    report.expectEqual(Set([1]), session.selectedTracks, cppID: id, what: "removed primary leaves surviving scope")
    session.adjustTrackScope(track: 1, action: .toggle)
    report.expectEqual(Set([1]), session.selectedTracks, cppID: id, what: "last scoped track cannot be removed")
    session.adjustTrackScope(track: 0, action: .range)
    report.expectEqual(Set([0, 1]), session.selectedTracks, cppID: id, what: "Shift extends range from primary")
    report.expectEqual(1, session.selectedTrack, cppID: id, what: "range keeps primary")
    let grid = PianoGrid(session: session)
    grid.performCommand(command: EditCommand.muteTracks.rawValue)
    report.expectEqual(Set([0, 1]), session.mutedTracks, cppID: id, what: "mute command uses entire track scope")
    grid.performCommand(command: EditCommand.muteTracks.rawValue)
    report.expect(session.mutedTracks.isEmpty, cppID: id, message: "all-muted scope toggles off together")
    grid.performCommand(command: EditCommand.soloTracks.rawValue)
    report.expectEqual(Set([0, 1]), session.soloedTracks, cppID: id, what: "solo command uses entire track scope")
    grid.performCommand(command: EditCommand.soloTracks.rawValue)
    report.expect(session.soloedTracks.isEmpty, cppID: id, message: "all-soloed scope toggles off together")
    baseline.expectUnchanged(report, fx.document, cppID: id, phase: "track scope and mix commands")
    report.expect(fx.document.moveTrack(1, to: 0), cppID: id, message: "move scoped track")
    report.expectEqual(0, session.selectedTrack, cppID: id, what: "primary follows moved identity")
    report.expectEqual(Set([0, 1]), session.selectedTracks, cppID: id, what: "scope follows both moved identities")
    report.expect(fx.document.history.undoDocument(), cppID: id, message: "undo scoped move")
    report.expectEqual(1, session.selectedTrack, cppID: id, what: "undo restores primary identity")
    report.expectEqual(Set([0, 1]), session.selectedTracks, cppID: id, what: "undo restores scope identities")
    session.adjustTrackScope(track: 0, action: .plain)
    report.expectEqual(Set([0]), session.selectedTracks, cppID: id, what: "plain click collapses scope")
}

@MainActor
func muteAndSoloHonorCancellationAndButtons(
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
    report.expect(h.beginPointer(x: mute.x, y: mute.y, button: 1, modifiers: 0),
                  cppID: id, message: "mute accepts press")
    report.expect(h.rows[0].mutePressed, cppID: id, message: "left press depresses mute")
    report.expect(h.beginPointer(x: title.x, y: title.y, button: 2, modifiers: 0),
                  cppID: id, message: "right press during held mute is handled")
    report.expect(h.rows[0].mutePressed && !h.menuOpen, cppID: id,
                  message: "additional right press does not replace held mute")
    report.expect(h.endPointer(x: title.x, y: title.y, button: 2, modifiers: 0),
                  cppID: id, message: "right release during held mute is handled")
    report.expect(!h.rows[0].mutePressed && !h.rows[0].muteChecked, cppID: id,
                  message: "wrong-button release cancels mute without toggling")

    // GridCancelReason raw values: FocusLost, PointerUngrabbed, Hidden, WindowDeactivated.
    for reason in 0...3 {
        report.expect(h.beginPointer(x: mute.x, y: mute.y, button: 1, modifiers: 0),
                      cppID: id, message: "cancel reason \(reason) accepts a fresh press")
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
    report.expect(h.beginPointer(x: solo.x, y: solo.y, button: 1, modifiers: 0),
                  cppID: id, message: "solo accepts press")
    report.expect(h.rows[0].soloPressed, cppID: id, message: "solo press is visible")
    report.expect(h.endPointer(x: solo.x, y: solo.y, button: 1, modifiers: 0),
                  cppID: id, message: "solo accepts release")
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
func scrollClampsAndRoutesKeyboardAndWheelInput(
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
func emptyTrackHeadersRejectInputWithoutMutation(
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
