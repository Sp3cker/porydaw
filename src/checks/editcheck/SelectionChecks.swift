import PorydawApp
import PorydawCore
import PorydawProjectService

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
    report.expectEqual([ids[0], ids[1]], session.selectedNoteOrder, cppID: sanitize,
                       what: "A001 unassigned and duplicate IDs are removed without changing order")
    report.expect(session.selectedNotes.contains(ids[0]), cppID: sanitize,
                  message: "A002 first selected note is indexed")
    report.expect(session.selectedNotes.contains(ids[1]), cppID: sanitize,
                  message: "A003 second selected note is indexed")
    report.expect(!session.selectedNotes.contains(ids[2]), cppID: sanitize,
                  message: "A004 unselected note is not indexed")
    report.expect(!session.selectedNotes.contains(invalid), cppID: sanitize,
                  message: "A005 unassigned note is not indexed")
    report.expectEqual([SessionChangeDomains.selection], changes, cppID: sanitize,
                       what: "A006 note selection publishes exactly once")
    changes.removeAll()
    session.setSelectedNotes([invalid, ids[0], ids[1], ids[1]])
    report.expect(changes.isEmpty, cppID: sanitize,
                  message: "A007 equivalent normalized selection publishes nothing")
    session.clearSelectedNotes()
    report.expectEqual([SessionChangeDomains.selection], changes, cppID: sanitize,
                       what: "A020 clearing notes publishes exactly once")
    report.expect(session.selectedNoteOrder.isEmpty, cppID: clear,
                  message: "A045 clearing populated note selection removes every note")
    report.expectEqual([SessionChangeDomains.selection], changes, cppID: clear,
                       what: "A046 clearing populated note selection publishes once")
    changes.removeAll()
    session.clearSelectedNotes()
    report.expect(changes.isEmpty, cppID: clear,
                  message: "A047 repeated empty clear publishes nothing")

    session.setSelectedNotes([ids[2], ids[0], ids[1]])
    changes.removeAll()
    document.deleteNotes([ids[1]])
    report.expectEqual([ids[2], ids[0]], session.selectedNoteOrder, cppID: reconcile,
                       what: "A048 reconciliation preserves reverse selection order rather than sorting by document order")
    report.expect(changes.count == 1 && changes[0].contains(.selection), cppID: reconcile,
                  message: "A049 one selection publication accompanies deletion reconciliation")
    changes.removeAll()
    document.renameTrack(0, to: "selection-reconcile")
    report.expect(changes.count == 1 && changes[0].contains(.document)
                  && session.selectedNoteOrder == [ids[2], ids[0]], cppID: reconcile,
                  message: "A050 document edit preserving valid notes emits no separate selection change")
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
    report.expectEqual(1, session.selectedTrack, cppID: gestures,
                       what: "A001 primary track transition chooses track one")
    report.expectEqual(Set([1]), session.selectedTracks, cppID: gestures,
                       what: "A002 primary transition selects its track scope")
    report.expectEqual([SessionChangeDomains.selection], changes, cppID: gestures,
                       what: "A003 one primary transition publication")
    changes.removeAll()
    session.adjustTrackScope(track: 3, action: .toggle)
    report.expectEqual(Set([1, 3]), session.selectedTracks, cppID: gestures,
                       what: "A004 toggle adds the secondary track")
    report.expectEqual([SessionChangeDomains.selection], changes, cppID: gestures,
                       what: "A005 toggle publishes once")
    changes.removeAll()
    session.adjustTrackScope(track: 1, action: .toggle)
    report.expectEqual(3, session.selectedTrack, cppID: gestures,
                       what: "A006 removing primary hands off to the surviving track")
    report.expectEqual(Set([3]), session.selectedTracks, cppID: gestures,
                       what: "A007 removing primary preserves surviving scope")
    report.expectEqual([SessionChangeDomains.selection], changes, cppID: gestures,
                       what: "A009 primary handoff publishes atomically")
    session.adjustTrackScope(track: 4, action: .toggle)
    changes.removeAll()
    session.adjustTrackScope(track: 3, action: .plain)
    report.expectEqual(3, session.selectedTrack, cppID: gestures,
                       what: "A016 plain gesture keeps its primary")
    report.expectEqual(Set([3]), session.selectedTracks, cppID: gestures,
                       what: "A017 plain gesture collapses multi-track scope")
    report.expectEqual([SessionChangeDomains.selection], changes, cppID: gestures,
                       what: "A019 collapsed scope publishes once")
    changes.removeAll()
    session.adjustTrackScope(track: 5, action: .range)
    report.expectEqual(Set([3, 4, 5]), session.selectedTracks, cppID: gestures,
                       what: "A022 range expands inclusively from primary to target")
    report.expectEqual([SessionChangeDomains.selection], changes, cppID: gestures,
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
    report.expectEqual(3, session.selectedTrack, cppID: gestures,
                       what: "A026 note handoff chooses the surviving primary")
    report.expectEqual(Set([3]), session.selectedTracks, cppID: gestures,
                       what: "A027 note handoff keeps surviving scope")
    report.expect(session.selectedNotes.isEmpty, cppID: gestures,
                  message: "A028 changing the selected note's primary clears it")
    report.expectEqual([SessionChangeDomains.selection], changes, cppID: gestures,
                       what: "A029 note and track transition publish together")

    changes.removeAll()
    session.adjustTrackScope(track: 16, action: .toggle)
    report.expectEqual(Set([3]), session.selectedTracks, cppID: bounds,
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
    report.expectEqual(4, session.selectedTrack, cppID: remapID,
                       what: "A080 primary follows track 1 to track 4")
    report.expectEqual(Set([2, 4]), session.selectedTracks, cppID: remapID,
                       what: "A081 scope follows tracks 0 and 1 to tracks 2 and 4")
    report.expectEqual([note], session.selectedNoteOrder, cppID: remapID,
                       what: "A082 selected note identity survives structural track moves")
    report.expect(changes.count == 1 && changes[0].contains(.document)
                  && changes[0].contains(.selection), cppID: remapID,
                  message: "A083 remap and selected scope publish one coalesced change")

    session.clearSelectedNotes()
    session.selectedTrack = 2
    session.adjustTrackScope(track: 0, action: .toggle)
    changes.removeAll()
    document.deleteTrack(2)
    report.expectEqual(2, session.selectedTrack, cppID: remapID,
                       what: "deleting a primary track falls back to its numeric position")
    report.expectEqual(Set([0, 2]), session.selectedTracks, cppID: remapID,
                       what: "deleting a primary track keeps surviving remapped scope plus fallback primary")
    report.expect(changes.count == 1 && changes[0].contains(.selection)
                  && changes[0].contains(.document), cppID: remapID,
                  message: "deleted-primary remap publishes one coalesced selection and document change")
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
    report.expectEqual(range, covered.activeTickRange, cppID: lanesID,
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
    report.expectEqual([volume, modulation], visibleSelectedLanes(covered), cppID: lanesID,
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
    report.expectEqual([volume], visibleSelectedLanes(ready), cppID: hiddenID,
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
