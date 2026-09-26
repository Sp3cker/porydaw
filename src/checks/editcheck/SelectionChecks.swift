import PorydawApp
import PorydawCore

@MainActor
func runClipboardSelectionChecks(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService) {
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(tick: 0, status: 0x90, data0: 60, data1: 90),
            .channel(tick: 12, status: 0x80, data0: 60),
            .channel(tick: 24, status: 0x90, data0: 62, data1: 91),
            .channel(tick: 36, status: 0x80, data0: 62),
            .channel(tick: 48, status: 0x90, data0: 64, data1: 92),
            .channel(tick: 60, status: 0x80, data0: 64),
        ], endTick: 96),
    ])
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName)
    guard document.notes(in: 0).count == 3 else {
        report.fail("clipboard/SelectionCheckTest::noteSelectionSanitizesAndExcludesTime",
                    "selection fixture must contain three distinct notes")
        return
    }
    clipboardLaneSelectionChecks(report, session: session)
    clipboardNoteSelectionChecks(report, session: session)
    clipboardTrackSelectionChecks(report, session: session)
    clipboardUnifiedTimeSelectionChecks(report, suite: suite, service: service)
    clipboardUnifiedModelChecks(report, suite: suite, service: service)

}

@MainActor
private func clipboardUnifiedModelChecks(_ report: CheckReport, suite: DocumentSession,
                                         service: ProjectService) {
    let id = "clipboard/SelectionCheckTest::trackScopeGesturesPreserveOrClearAtTheRightBoundary"
    let doc = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(tick: 48, status: 0x90, data0: 60, data1: 90),
            .channel(tick: 60, status: 0x80, data0: 60),
        ], endTick: 96),
    ]), config: suite.document.state.config, source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    for _ in doc.engineTracks.usedTrackCount..<3 {
        guard doc.addTrack(voice: 0) != nil else {
            report.fail(id, "selection fixture cannot provision three engine tracks")
            return
        }
    }
    let session = DocumentSession(document: doc, service: service, lease: suite.bankLease,
                                  slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName)
    var transitions: [SelectionTransition] = []
    let observer = session.addSelectionTransitionObserver { transitions.append($0) }
    defer { session.removeSelectionTransitionObserver(observer) }
    session.selectPrimaryTrack(0)
    let time = AutomationTimeSelection(range: TimeRange(startTick: 12, endTick: 36),
                                        scope: .tracks([0, 1]))
    session.applyTimeSelection(time)
    report.expect(session.timeSelection == time, cppID: id,
                  message: "a track-scoped range is owned by the document session")
    session.adjustTrackScope(track: 1, action: .plain)
    report.expect(session.timeSelection == nil, cppID: id,
                  message: "plain on another track clears the time selection")
    session.applyTimeSelection(time)
    session.adjustTrackScope(track: 1, action: .plain)
    report.expect(session.timeSelection?.range == time.range, cppID: id,
                  message: "plain on the primary track preserves the time interval")
    report.expect(session.timeSelection?.scope == .tracks([1]), cppID: id,
                  message: "plain on the primary track narrows the selected scope")
    session.applyTimeSelection(time)
    session.adjustTrackScope(track: 1, action: .toggle)
    report.expect(session.selectedTrack == 0, cppID: id,
                  message: "toggle hands primary to the surviving track")
    report.expect(session.timeSelection?.scope == .tracks([0]), cppID: id,
                  message: "toggle preserves the time interval on the surviving scope")
    report.expect(transitions.last?.previousTrackTime.trackScope == [0, 1]
                  && transitions.last?.trackTime.trackScope == [0], cppID: id,
                  message: "the transition reports the previous and current track-time scope")
    session.adjustTrackScope(track: 2, action: .range)
    report.expect(session.selectedTracks == [0, 1, 2], cppID: id,
                  message: "range expands inclusively from primary to target")
    report.expect(session.timeSelection?.scope == .tracks([0, 1, 2]), cppID: id,
                  message: "range changes the authoritative time-selection scope")
    guard let note = doc.notes(in: 0).first else {
        report.fail(id, "the note handoff fixture has no note")
        return
    }
    session.setSelectedNotes([note.id])
    report.expect(session.timeSelection == nil, cppID: id,
                  message: "a note selection clears the active time selection")
    session.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 12, endTick: 36), scope: .tracks([0, 2])))
    guard doc.moveTrack(2, to: 1) else {
        report.fail(id, "cannot move selected track for scope remap")
        return
    }
    report.expect(session.timeSelection?.scope == .tracks([0, 1]), cppID: id,
                  message: "remap moves the stored scope with the selected track")
}

@MainActor
private func clipboardNoteSelectionChecks(_ report: CheckReport, session: DocumentSession) {
    let sanitize = "clipboard/SelectionCheckTest::noteSelectionSanitizesAndExcludesTime"
    let clear = "clipboard/SelectionCheckTest::clearOperationsPreserveTheOtherSelection"
    let reconcile = "clipboard/SelectionCheckTest::reconciliationPreservesSelectionOrder"
    let document = session.document
    let ids = document.notes(in: 0).map(\.id)
    let invalid = NoteID()
    var changes: [SessionChangeDomains] = []
    session.onChange = { changes.append($0.domains) }
    defer { session.onChange = nil }

    session.setSelectedNotes([invalid, ids[0], ids[0], ids[1]])
    report.expectEqual(expected: [ids[0], ids[1]], actual: session.selectedNoteOrder, cppID: sanitize,
                       what: "A001 unassigned and duplicate IDs are removed without changing order")
    report.expect(session.selectedNotes.contains(ids[0]), cppID: sanitize,
                  message: "A002 first selected note is indexed")
    report.expect(session.selectedNotes.contains(ids[1]), cppID: sanitize,
                  message: "A003 second selected note is indexed")
    report.expect(!session.selectedNotes.contains(ids[2]), cppID: sanitize,
                  message: "A004 unselected note is not indexed")
    report.expect(!session.selectedNotes.contains(invalid), cppID: sanitize,
                  message: "A005 unassigned note is not indexed")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: sanitize,
                       what: "A006 note selection publishes exactly once")
    changes.removeAll()
    session.setSelectedNotes([invalid, ids[0], ids[1], ids[1]])
    report.expect(changes.isEmpty, cppID: sanitize,
                  message: "A007 equivalent normalized selection publishes nothing")
    session.clearSelectedNotes()
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: sanitize,
                       what: "A020 clearing notes publishes exactly once")
    report.expect(session.selectedNoteOrder.isEmpty, cppID: clear,
                  message: "A045 clearing populated note selection removes every note")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: clear,
                       what: "A046 clearing populated note selection publishes once")
    changes.removeAll()
    session.clearSelectedNotes()
    report.expect(changes.isEmpty, cppID: clear,
                  message: "A047 repeated empty clear publishes nothing")

    session.setSelectedNotes([ids[2], ids[0], ids[1]])
    changes.removeAll()
    document.deleteNotes([ids[1]])
    report.expectEqual(expected: [ids[2], ids[0]], actual: session.selectedNoteOrder, cppID: reconcile,
                       what: "A048 reconciliation preserves reverse selection order rather than sorting by document order")
    report.expect(changes.count == 1 && changes[0].contains(.selection), cppID: reconcile,
                  message: "A049 one selection publication accompanies deletion reconciliation")
    changes.removeAll()
    document.renameTrack(0, to: "selection-reconcile")
    report.expect(changes.count == 1 && changes[0] == [.document, .dirty, .history]
                  && session.selectedNoteOrder == [ids[2], ids[0]], cppID: reconcile,
                  message: "A050 idempotent reconciliation publishes no selection change")
    changes.removeAll()
    document.deleteNotes([ids[0], ids[2]])
    report.expect(session.selectedNoteOrder.isEmpty && session.selectedNotes.isEmpty,
                  cppID: reconcile, message: "A051 reconciliation to empty removes membership")
    report.expect(changes.count == 1 && changes[0].contains(.selection), cppID: reconcile,
                  message: "A052 reconciliation to empty publishes once")
}

@MainActor
private func clipboardTrackSelectionChecks(_ report: CheckReport, session: DocumentSession) {
    let gestures = "clipboard/SelectionCheckTest::trackScopeGesturesPreserveOrClearAtTheRightBoundary"
    let bounds = "clipboard/SelectionCheckTest::outOfRangeTrackMasksAreIgnored"
    let document = session.document
    for _ in document.engineTracks.usedTrackCount..<6 {
        guard document.addTrack(voice: 0) != nil else {
            report.fail(gestures, "selection fixture cannot provision six engine tracks")
            return
        }
    }
    var changes: [SessionChangeDomains] = []
    session.onChange = { changes.append($0.domains) }
    defer { session.onChange = nil }
    session.selectedTrack = 1
    report.expectEqual(expected: 1, actual: session.selectedTrack, cppID: gestures,
                       what: "A001 primary track transition chooses track one")
    report.expectEqual(expected: Set([1]), actual: session.selectedTracks, cppID: gestures,
                       what: "A002 primary transition selects its track scope")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
                       what: "A003 one primary transition publication")
    changes.removeAll()
    session.adjustTrackScope(track: 3, action: .toggle)
    report.expectEqual(expected: Set([1, 3]), actual: session.selectedTracks, cppID: gestures,
                       what: "A004 toggle adds the secondary track")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
                       what: "A005 toggle publishes once")
    changes.removeAll()
    session.adjustTrackScope(track: 1, action: .toggle)
    report.expectEqual(expected: 3, actual: session.selectedTrack, cppID: gestures,
                       what: "A006 removing primary hands off to the surviving track")
    report.expectEqual(expected: Set([3]), actual: session.selectedTracks, cppID: gestures,
                       what: "A007 removing primary preserves surviving scope")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
                       what: "A009 primary handoff publishes atomically")
    session.adjustTrackScope(track: 4, action: .toggle)
    changes.removeAll()
    session.adjustTrackScope(track: 3, action: .plain)
    report.expectEqual(expected: 3, actual: session.selectedTrack, cppID: gestures,
                       what: "A016 plain gesture keeps its primary")
    report.expectEqual(expected: Set([3]), actual: session.selectedTracks, cppID: gestures,
                       what: "A017 plain gesture collapses multi-track scope")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
                       what: "A019 collapsed scope publishes once")
    changes.removeAll()
    session.adjustTrackScope(track: 5, action: .range)
    report.expectEqual(expected: Set([3, 4, 5]), actual: session.selectedTracks, cppID: gestures,
                       what: "A022 range expands inclusively from primary to target")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
                       what: "A023 range publishes once")

    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 3, action: .toggle)
    guard let note = try? document.addNotes([
        NewNote(track: 1, tick: 72, pitch: 67, duration: 12, velocity: 93),
    ]).first else {
        report.fail(gestures, "note-selection handoff fixture could not insert a note")
        return
    }
    session.setSelectedNotes([note])
    changes.removeAll()
    session.adjustTrackScope(track: 1, action: .toggle)
    report.expectEqual(expected: 3, actual: session.selectedTrack, cppID: gestures,
                       what: "A026 note handoff chooses the surviving primary")
    report.expectEqual(expected: Set([3]), actual: session.selectedTracks, cppID: gestures,
                       what: "A027 note handoff keeps surviving scope")
    report.expect(session.selectedNotes.isEmpty, cppID: gestures,
                  message: "A028 changing the selected note's primary clears it")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
                       what: "A029 note and track transition publish together")

    changes.removeAll()
    session.adjustTrackScope(track: 16, action: .toggle)
    report.expectEqual(expected: Set([3]), actual: session.selectedTracks, cppID: bounds,
                       what: "A060 out-of-range track cannot join the scope")
    report.expect(changes.isEmpty, cppID: bounds,
                  message: "A061 ignored out-of-range action publishes nothing")
    let remapID = "clipboard/SelectionCheckTest::remapPreservesMeaningfulSelection"
    session.selectedTrack = 1
    session.adjustTrackScope(track: 0, action: .toggle)
    session.setSelectedNotes([note])
    changes.removeAll()
    guard session.withStateChanges({
        document.moveTrack(1, to: 4) && document.moveTrack(0, to: 2)
    }) else {
        report.fail(remapID, "selection remap fixture could not move tracks 1 and 0")
        return
    }
    report.expectEqual(expected: 4, actual: session.selectedTrack, cppID: remapID,
                       what: "A080 primary follows track 1 to track 4")
    report.expectEqual(expected: Set([2, 4]), actual: session.selectedTracks, cppID: remapID,
                       what: "A081 scope follows tracks 0 and 1 to tracks 2 and 4")
    report.expectEqual(expected: [note], actual: session.selectedNoteOrder, cppID: remapID,
                       what: "A082 selected note identity survives structural track moves")
    report.expect(changes.count == 1 && changes[0].contains(.document)
                  && changes[0].contains(.selection), cppID: remapID,
                  message: "A083 remap and selected scope publish one coalesced change")

    session.clearSelectedNotes()
    session.selectedTrack = 2
    session.adjustTrackScope(track: 0, action: .toggle)
    changes.removeAll()
    document.deleteTrack(2)
    report.expectEqual(expected: 2, actual: session.selectedTrack, cppID: remapID,
                       what: "deleting a primary track falls back to its numeric position")
    report.expectEqual(expected: Set([0, 2]), actual: session.selectedTracks, cppID: remapID,
                       what: "deleting a primary track keeps surviving remapped scope plus fallback primary")
    report.expectEqual(expected: [SessionChangeDomains([.document, .dirty, .history])],
                       actual: changes, cppID: remapID,
                       what: "numeric fallback preserving scope publishes one document change without selection churn")
    document.deleteTrack(4)
    document.deleteTrack(3)
    document.deleteTrack(2)
    changes.removeAll()
    document.deleteTrack(1)
    report.expectEqual(expected: 0, actual: session.selectedTrack, cppID: remapID,
                       what: "A093 deleting every track above the fallback clamps the primary to track zero")
    report.expectEqual(expected: Set([0]), actual: session.selectedTracks, cppID: remapID,
                       what: "A094 deleting every track above the fallback leaves the scope on track zero")
}

@MainActor
private func clipboardLaneSelectionChecks(_ report: CheckReport, session: DocumentSession) {
    let emptyID = "clipboard/AutomationCoverageTest::emptySelectionAndEndpointPayload"
    let lanesID = "clipboard/AutomationCoverageTest::laneScopeCoverage"
    let tracksID = "clipboard/AutomationCoverageTest::trackScopeSeparatesLaneAndNodeCoverage"
    let hiddenID = "clipboard/AutomationCoverageTest::hiddenLanesAreNotCovered"
    let factsID = "clipboard/AutomationCoverageTest::documentFactsFollowIdentity"
    let document = session.document
    let pan = AutomationParameter.controlChange(track: 0, controller: 10)
    let volume = AutomationParameter.controlChange(track: 0, controller: 7)
    let modulation = AutomationParameter.controlChange(track: 0, controller: 21)
    func stack(_ selection: AutomationTimeSelection?, ready: Bool = true) -> AutomationRowStack {
        AutomationRowStack.build(document: document, primaryTrack: 0, selection: selection,
                                 ready: ready, songEndTick: 96)
    }
    let empty = stack(nil)
    func visibleSelectedLanes(_ rows: AutomationRowStack) -> [AutomationParameter] {
        rows.visibleRows.filter { !$0.parameter.isTempo && $0.coversLane }.map(\.parameter)
    }
    report.expect(empty.activeTickRange == nil, cppID: emptyID,
                  message: "A002 empty selection has no active tick range")
    for (site, parameter) in [("A003-A004", AutomationParameter.tempo),
                              ("A005-A006", volume)] {
        report.expect(empty.row(for: parameter)?.coversLane == false
                      && empty.row(for: parameter)?.coversNodes == false,
                      cppID: emptyID, message: "\(site) empty selection covers neither lane nor nodes")
    }
    report.expect(empty.row(for: .controlChange(track: 0, controller: 99)) == nil,
                  cppID: emptyID, message: "A007-A008 unsupported controller covers nothing")
    report.expect(visibleSelectedLanes(empty).isEmpty, cppID: emptyID,
                  message: "A009 empty selection exposes no selected visible lanes")
    let range = TimeRange(startTick: 24, endTick: 48)
    let selection = AutomationTimeSelection(range: range, scope: .lanes,
                                            lanes: [volume, modulation], tempo: true)
    let covered = stack(selection)
    report.expectEqual(expected: range, actual: covered.activeTickRange, cppID: lanesID,
                       what: "A013 lane-scoped range keeps its tick endpoints")
    for (site, parameter) in [("A014-A015", AutomationParameter.tempo),
                              ("A016-A017", volume), ("A018-A019", modulation)] {
        report.expect(covered.row(for: parameter)?.coversLane == true
                      && covered.row(for: parameter)?.coversNodes == true,
                      cppID: lanesID, message: "\(site) selected row covers lane and nodes")
    }
    report.expect(covered.row(for: pan)?.coversLane == false
                  && covered.row(for: pan)?.coversNodes == false,
                  cppID: lanesID, message: "A020-A021 unselected supported controller stays uncovered")
    report.expect(covered.row(for: .controlChange(track: 0, controller: 99)) == nil,
                  cppID: lanesID, message: "A022-A023 unsupported controller has no row")
    report.expectEqual(expected: [volume, modulation], actual: visibleSelectedLanes(covered), cppID: lanesID,
                       what: "A024 only selected supported lanes are visible in catalog order")
    let noTempo = stack(AutomationTimeSelection(range: range, scope: .lanes,
                                                 lanes: [volume], tempo: false))
    report.expect(noTempo.row(for: .tempo)?.coversLane == false
                  && noTempo.row(for: .tempo)?.coversNodes == false,
                  cppID: lanesID, message: "A025-A026 lane scope excludes unselected Tempo")

    let trackSelection = AutomationTimeSelection(range: range, scope: .tracks([0]))
    let trackStack = stack(trackSelection)
    report.expect(trackStack.row(for: volume)?.coversLane == false
                  && trackStack.row(for: volume)?.coversNodes == true,
                  cppID: tracksID, message: "A030-A031 track scope covers CC nodes, not entire lane")
    report.expect(trackStack.row(for: .tempo)?.coversLane == true,
                  cppID: tracksID, message: "A028 full track scope covers Tempo lane")
    report.expect(trackStack.row(for: .tempo)?.coversNodes == true,
                  cppID: tracksID, message: "A029 full track scope covers Tempo nodes")
    guard document.addTrack(voice: 0) != nil else {
        report.fail(tracksID, "cannot create the secondary track for partial Tempo coverage")
        return
    }
    let partial = stack(trackSelection)
    report.expect(partial.row(for: .tempo)?.coversLane == false,
                  cppID: tracksID, message: "A033 partial track scope excludes Tempo lane")
    report.expect(partial.row(for: .tempo)?.coversNodes == false,
                  cppID: tracksID, message: "A034 partial track scope excludes Tempo nodes")

    let ready = stack(AutomationTimeSelection(range: range, scope: .lanes,
                                               lanes: [volume, .controlChange(track: 0,
                                                   controller: 99)]))
    report.expect(ready.row(for: volume)?.coversLane == true, cppID: hiddenID,
                  message: "A036 ready selected CC7 lane is covered")
    report.expect(ready.row(for: volume)?.coversNodes == true, cppID: hiddenID,
                  message: "A037 ready selected CC7 nodes are covered")
    report.expect(ready.row(for: pan)?.coversLane == false, cppID: hiddenID,
                  message: "A038 ready unselected CC10 lane is uncovered")
    report.expect(ready.row(for: pan)?.coversNodes == false, cppID: hiddenID,
                  message: "A039 ready unselected CC10 nodes are uncovered")
    report.expectEqual(expected: [volume], actual: visibleSelectedLanes(ready), cppID: hiddenID,
                       what: "A042 ready model exposes only selected supported lanes")

    let hidden = stack(AutomationTimeSelection(range: range, scope: .lanes,
                                                lanes: [volume, .controlChange(track: 0,
                                                    controller: 99)]), ready: false)
    report.expect(hidden.row(for: volume) != nil, cppID: hiddenID,
                  message: "A043 page-not-ready still carries supported controller row")
    report.expect(hidden.row(for: volume)?.coversLane == false
                  && hidden.row(for: volume)?.coversNodes == false,
                  cppID: hiddenID, message: "A044-A045 hidden row covers nothing")
    report.expect(hidden.row(for: .controlChange(track: 0, controller: 99)) == nil,
                  cppID: hiddenID, message: "A040-A041 unsupported controller stays absent")
    report.expect(visibleSelectedLanes(hidden).isEmpty, cppID: hiddenID,
                  message: "A046 page-not-ready exposes no selected visible lanes")
    let prior = stack(selection).row(for: volume)?.eventCount
    document.writeLane(track: 0, lane: .controller(7), from: 0,
                       through: TimeDefaults.noTick, points: [LaneWrite(tick: 24, value: 64)])
    let after = stack(selection).row(for: volume)?.eventCount
    report.expect(prior == 0, cppID: factsID,
                  message: "A048 initially empty controller row has zero written events")
    report.expect(after == 1, cppID: factsID,
                  message: "A049 rebuilding after a write counts its event")
    report.expect(stack(selection).row(for: pan) != nil, cppID: factsID,
                  message: "A050 supported controller is present without a selection")
    report.expect(stack(selection).row(for: .controlChange(track: 0, controller: 99)) == nil,
                  cppID: factsID, message: "A051 unsupported controller is absent")
}

@MainActor
private func clipboardUnifiedTimeSelectionChecks(_ report: CheckReport, suite: DocumentSession,
                                                 service: ProjectService) {
    let sanitize = "clipboard/SelectionCheckTest::noteSelectionSanitizesAndExcludesTime"
    let clear = "clipboard/SelectionCheckTest::clearOperationsPreserveTheOtherSelection"
    let commit = "clipboard/SelectionCheckTest::timeSelectionAndScopeCommitAtomically"
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(tick: 0, status: 0x90, data0: 60, data1: 90),
            .channel(tick: 12, status: 0x80, data0: 60),
            .channel(tick: 24, status: 0x90, data0: 62, data1: 91),
            .channel(tick: 36, status: 0x80, data0: 62),
            .channel(tick: 48, status: 0x90, data0: 64, data1: 92),
            .channel(tick: 60, status: 0x80, data0: 64),
        ], endTick: 96),
    ])
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName)
    guard document.notes(in: 0).count == 3 else {
        report.fail(sanitize, "unified selection fixture must contain three distinct notes")
        return
    }
    let page = AutomationPage()
    page.attach(session: session, palette: GridPalette())
    defer { page.detach() }
    let note = document.notes(in: 0)[0].id
    let parameter = AutomationParameter.controlChange(track: 0, controller: 7)
    var changes: [SessionChangeDomains] = []
    var transitions: [SelectionTransition] = []
    let observer = session.addSelectionTransitionObserver { transitions.append($0) }
    defer { session.removeSelectionTransitionObserver(observer) }
    var availability = 0
    page.onCommandAvailabilityChanged = { availability += 1 }
    session.onChange = { changes.append($0.domains) }
    defer { session.onChange = nil }

    session.setSelectedNotes([note])
    changes.removeAll()
    let revision = document.revision
    let initialBuilds = page.selectionBuildCount
    let laneTime = AutomationTimeSelection(range: TimeRange(startTick: 10, endTick: 20),
                                           scope: .lanes, lanes: [parameter, .tempo], tempo: true)
    page.applyTimeSelection(laneTime)
    report.expect(session.selectedNoteOrder.isEmpty, cppID: sanitize,
                  message: "A008 committing an active range clears the competing note selection")
    report.expect(page.selection?.isActive == true, cppID: sanitize,
                  message: "A009 committed time selection is active")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: changes, cppID: sanitize,
                       what: "A010 time commit publishes one coalesced session selection change")
    report.expectEqual(expected: initialBuilds + 1, actual: page.selectionBuildCount, cppID: sanitize,
                       what: "A010 session selection publication rebuilds the page selection once")
    report.expectEqual(expected: revision, actual: document.revision, cppID: sanitize,
                       what: "A010 time selection never edits the song")
    report.expect(page.selection?.covers(.tempo, usedTracks: [0]) == true, cppID: sanitize,
                  message: "tempo coverage survives lane sanitization")
    report.expect(page.selection?.covers(parameter, usedTracks: [0]) == true, cppID: sanitize,
                  message: "valid control-change lane remains covered")
    changes.removeAll()
    session.setSelectedNotes([NoteID()])
    report.expect(page.selection?.isActive == true, cppID: sanitize,
                  message: "A011 empty note guard preserves the active time selection")
    report.expect(page.selection?.lanes == [parameter], cppID: sanitize,
                  message: "A011 empty note guard retains sanitized lane coverage")
    report.expect(session.selectedNoteOrder.isEmpty, cppID: sanitize,
                  message: "A012 empty note guard leaves no notes selected")
    report.expect(changes.isEmpty, cppID: sanitize,
                  message: "A013 empty note guard publishes nothing")
    page.applyTimeSelection(page.selection)
    report.expect(changes.isEmpty, cppID: commit,
                  message: "A042 equivalent time and scope commit publishes nothing")
    let availabilityBeforeClear = availability
    page.clearTimeSelection()
    report.expect(page.selection == nil, cppID: sanitize,
                  message: "A022 clearing the committed time selection deactivates it")
    report.expect(session.selectedNoteOrder.isEmpty, cppID: sanitize,
                  message: "A023 clearing time leaves the empty note selection empty")
    report.expect(availability == availabilityBeforeClear + 1, cppID: sanitize,
                  message: "A024 clearing time publishes one page availability change")
    report.expect(transitions.last?.trackTime.active == false, cppID: sanitize,
                  message: "clearing time publishes an inactive transition payload")
    changes.removeAll()
    session.setSelectedNotes([note])
    changes.removeAll()
    page.clearTimeSelection()
    report.expect(session.selectedNoteOrder == [note], cppID: clear,
                  message: "A017 inactive time commit preserves the note selection")
    report.expect(changes.isEmpty, cppID: clear,
                  message: "A019 inactive time commit publishes nothing")
    session.clearSelectedNotes()
    changes.removeAll()
    session.clearSelectedNotes()
    page.clearTimeSelection()
    report.expect(page.selection == nil && session.selectedNoteOrder.isEmpty, cppID: clear,
                  message: "A021 clearing empty selections changes neither owner")
    report.expect(changes.isEmpty, cppID: clear,
                  message: "A021 clearing empty selections publishes nothing")

    let trackTime = AutomationTimeSelection(range: TimeRange(startTick: 40, endTick: 80),
                                            scope: .tracks([0, 20]))
    page.applyTimeSelection(trackTime)
    report.expectEqual(expected: TimeRange(startTick: 40, endTick: 80),
                       actual: page.selection?.range, cppID: commit,
                       what: "A025-A026 track-scoped commit keeps its tick endpoints")
    report.expectEqual(expected: AutomationTimeSelection.Scope.tracks([0]),
                       actual: page.selection?.scope, cppID: commit,
                       what: "A027 resolved scope drops the out-of-range track")
    report.expectEqual(expected: TrackTimeSelection(startTick: 40, endTick: 80, trackScope: [0]),
                       actual: transitions.last?.trackTime, cppID: commit,
                       what: "A028 transition exposes the committed endpoint and scope payload")
    report.expect(page.selectionCommandAvailable(command: .copy), cppID: commit,
                  message: "selected track interval exposes copy when it contains a note")
    let availabilityBeforeSecondCommit = availability
    page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 50, endTick: 90), scope: .tracks([0])))
    report.expectEqual(expected: TrackTimeSelection(startTick: 40, endTick: 80, trackScope: [0]),
                       actual: transitions.last?.previousTrackTime, cppID: commit,
                       what: "A035 previous transition endpoint and scope remain available")
    report.expectEqual(expected: TrackTimeSelection(startTick: 50, endTick: 90, trackScope: [0]),
                       actual: transitions.last?.trackTime, cppID: commit,
                       what: "A036 next transition endpoint and scope replace the previous selection")
    report.expect(availability == availabilityBeforeSecondCommit + 1, cppID: commit,
                  message: "A037 second track-scoped commit publishes one page availability change")
    changes.removeAll()
    let availabilityBeforeEmptyNoteClear = availability
    session.clearSelectedNotes()
    report.expect(page.selection?.isActive == true, cppID: clear,
                  message: "A043 clearing notes preserves the active time selection")
    report.expect(changes.isEmpty && availability == availabilityBeforeEmptyNoteClear, cppID: clear,
                  message: "A044 clearing the empty note selection publishes nothing")
    let selectionBeforeDetach = session.timeSelection
    page.detach()
    report.expect(session.timeSelection == selectionBeforeDetach, cppID: commit,
                  message: "detaching a drawer leaves document-session selection intact")
    page.attach(session: session, palette: GridPalette())
    report.expect(page.selection == selectionBeforeDetach, cppID: commit,
                  message: "reattached drawer projects the authoritative session selection")
    let otherSession = DocumentSession(document: SongDocument(
        file: file, config: suite.document.state.config, source: suite.document.source,
        trackBudget: suite.document.trackBudget), service: service,
        lease: suite.bankLease, slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName)
    report.expect(otherSession.timeSelection == nil, cppID: commit,
                  message: "a fresh document session starts without another tab's time selection")
    let coverage = "clipboard/SelectionCheckTest::coverageQueriesAndLaneScopeSanitization"
    let remap = "clipboard/SelectionCheckTest::remapPreservesMeaningfulSelection"
    let expanding = AutomationTimeSelection(range: TimeRange(startTick: 10, endTick: 20),
                                            scope: .tracks([0, 1]))
    session.applyTimeSelection(expanding)
    report.expect(session.timeSelection?.scope == .tracks([0, 1]), cppID: coverage,
                  message: "track scope preserves an unused valid track bit")
    report.expect(!session.timeSelectionCoversTrack(1), cppID: coverage,
                  message: "coverage resolves only against used tracks")
    report.expect(session.timeSelectionCoversTempo(), cppID: coverage,
                  message: "a scope covering every used track covers global Tempo")
    guard document.addTrack(voice: 0) == 1 else {
        report.fail(coverage, "cannot add track to test stored scope expansion")
        return
    }
    report.expect(session.timeSelectionCoversTrack(1), cppID: coverage,
                  message: "a newly added track inherits its stored selection bit")
    report.expect(session.selectedTracks == [0, 1], cppID: coverage,
                  message: "a newly used track appears in the resolved scope transition")
    session.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 10, endTick: 20), scope: .tracks([0])))
    report.expect(!session.timeSelectionCoversTempo(), cppID: coverage,
                  message: "partial used-track coverage excludes global Tempo")
    report.expect(session.timeSelectionCoversTrack(0), cppID: coverage,
                  message: "a track-scoped selection covers its used track")
    session.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 10, endTick: 20), scope: .lanes,
        lanes: [.controlChange(track: -1, controller: 7),
                .controlChange(track: 16, controller: 7)]))
    report.expect(session.timeSelection == nil, cppID: coverage,
                  message: "an active lane selection without lanes or tempo is dropped")
    session.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 10, endTick: 20), scope: .lanes, tempo: true))
    report.expect(session.timeSelectionCoversTempo(), cppID: coverage,
                  message: "a tempo-only lane selection survives sanitization")
    report.expect(!session.timeSelectionCoversTrack(0), cppID: coverage,
                  message: "a lane selection does not cover an entire track")
    session.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 10, endTick: 20), scope: .lanes,
        lanes: [.controlChange(track: 1, controller: 7)]))
    document.deleteTrack(1)
    report.expect(session.timeSelection == nil, cppID: remap,
                  message: "lane scopes remap and sanitize away a deleted track")
    guard document.addTrack(voice: 0) == 1 else {
        report.fail(remap, "cannot restore a secondary track for primary deletion")
        return
    }
    session.selectPrimaryTrack(1)
    session.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 10, endTick: 20), scope: .tracks([1])))
    document.deleteTrack(1)
    report.expect(session.timeSelection == nil, cppID: remap,
                  message: "a deleted primary clears the track-scoped time selection")
}
