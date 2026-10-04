import PorydawApp
import PorydawCore

@MainActor
func clipboardUnifiedModelChecks(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "clipboard/SelectionCheckTest::trackScopeGesturesPreserveOrClearAtTheRightBoundary"
    let doc = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .channel(tick: 48, status: 0x90, data0: 60, data1: 90),
                        .channel(tick: 60, status: 0x80, data0: 60),
                    ], endTick: 96)
            ]), config: suite.document.state.config, source: suite.document.source,
        trackBudget: suite.document.trackBudget)
    for _ in doc.engineTracks.usedTrackCount..<3 {
        guard doc.addTrack(voice: 0) != nil else {
            report.fail(id, "selection fixture cannot provision three engine tracks")
            return
        }
    }
    let session = DocumentSession(
        document: doc, service: service, lease: suite.bankLease,
        slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName)
    var transitions: [SelectionTransition] = []
    let observer = session.addSelectionTransitionObserver { transitions.append($0) }
    defer { session.removeSelectionTransitionObserver(observer) }
    session.selectPrimaryTrack(0)
    let time = AutomationTimeSelection(
        range: TimeRange(startTick: 12, endTick: 36),
        scope: .tracks([0, 1]))
    session.applyTimeSelection(time)
    report.expect(
        session.timeSelection == time, cppID: id,
        message: "a track-scoped range is owned by the document session")
    session.adjustTrackScope(track: 1, action: .plain)
    report.expect(
        session.timeSelection == nil, cppID: id,
        message: "plain on another track clears the time selection")
    session.applyTimeSelection(time)
    session.adjustTrackScope(track: 1, action: .plain)
    report.expect(
        session.timeSelection?.range == time.range, cppID: id,
        message: "plain on the primary track preserves the time interval")
    report.expect(
        session.timeSelection?.scope == .tracks([1]), cppID: id,
        message: "plain on the primary track narrows the selected scope")
    session.applyTimeSelection(time)
    session.adjustTrackScope(track: 1, action: .toggle)
    report.expect(
        session.selectedTrack == 0, cppID: id,
        message: "toggle hands primary to the surviving track")
    report.expect(
        session.timeSelection?.scope == .tracks([0]), cppID: id,
        message: "toggle preserves the time interval on the surviving scope")
    report.expect(
        transitions.last?.previousTrackTime.trackScope == [0, 1]
            && transitions.last?.trackTime.trackScope == [0], cppID: id,
        message: "the transition reports the previous and current track-time scope")
    session.adjustTrackScope(track: 2, action: .range)
    report.expect(
        session.selectedTracks == [0, 1, 2], cppID: id,
        message: "range expands inclusively from primary to target")
    report.expect(
        session.timeSelection?.scope == .tracks([0, 1, 2]), cppID: id,
        message: "range changes the authoritative time-selection scope")
    guard let note = doc.notes(in: 0).first else {
        report.fail(id, "the note handoff fixture has no note")
        return
    }
    session.setSelectedNotes([note.id])
    report.expect(
        session.timeSelection == nil, cppID: id,
        message: "a note selection clears the active time selection")
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 12, endTick: 36), scope: .tracks([0, 2])))
    guard doc.moveTrack(2, to: 1) else {
        report.fail(id, "cannot move selected track for scope remap")
        return
    }
    report.expect(
        session.timeSelection?.scope == .tracks([0, 1]), cppID: id,
        message: "remap moves the stored scope with the selected track")
}

@MainActor
func clipboardTrackSelectionChecks(_ report: CheckReport, session: DocumentSession) {
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
    report.expectEqual(
        expected: 1, actual: session.selectedTrack, cppID: gestures,
        what: "A001 primary track transition chooses track one")
    report.expectEqual(
        expected: Set([1]), actual: session.selectedTracks, cppID: gestures,
        what: "A002 primary transition selects its track scope")
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
        what: "A003 one primary transition publication")
    changes.removeAll()
    session.adjustTrackScope(track: 3, action: .toggle)
    report.expectEqual(
        expected: Set([1, 3]), actual: session.selectedTracks, cppID: gestures,
        what: "A004 toggle adds the secondary track")
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
        what: "A005 toggle publishes once")
    changes.removeAll()
    session.adjustTrackScope(track: 1, action: .toggle)
    report.expectEqual(
        expected: 3, actual: session.selectedTrack, cppID: gestures,
        what: "A006 removing primary hands off to the surviving track")
    report.expectEqual(
        expected: Set([3]), actual: session.selectedTracks, cppID: gestures,
        what: "A007 removing primary preserves surviving scope")
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
        what: "A009 primary handoff publishes atomically")
    session.adjustTrackScope(track: 4, action: .toggle)
    changes.removeAll()
    session.adjustTrackScope(track: 3, action: .plain)
    report.expectEqual(
        expected: 3, actual: session.selectedTrack, cppID: gestures,
        what: "A016 plain gesture keeps its primary")
    report.expectEqual(
        expected: Set([3]), actual: session.selectedTracks, cppID: gestures,
        what: "A017 plain gesture collapses multi-track scope")
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
        what: "A019 collapsed scope publishes once")
    changes.removeAll()
    session.adjustTrackScope(track: 5, action: .range)
    report.expectEqual(
        expected: Set([3, 4, 5]), actual: session.selectedTracks, cppID: gestures,
        what: "A022 range expands inclusively from primary to target")
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
        what: "A023 range publishes once")

    session.adjustTrackScope(track: 1, action: .plain)
    session.adjustTrackScope(track: 3, action: .toggle)
    guard
        let note = try? document.addNotes([
            NewNote(track: 1, tick: 72, pitch: 67, duration: 12, velocity: 93)
        ]).first
    else {
        report.fail(gestures, "note-selection handoff fixture could not insert a note")
        return
    }
    session.setSelectedNotes([note])
    changes.removeAll()
    session.adjustTrackScope(track: 1, action: .toggle)
    report.expectEqual(
        expected: 3, actual: session.selectedTrack, cppID: gestures,
        what: "A026 note handoff chooses the surviving primary")
    report.expectEqual(
        expected: Set([3]), actual: session.selectedTracks, cppID: gestures,
        what: "A027 note handoff keeps surviving scope")
    report.expect(
        session.selectedNotes.isEmpty, cppID: gestures,
        message: "A028 changing the selected note's primary clears it")
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: gestures,
        what: "A029 note and track transition publish together")

    changes.removeAll()
    session.adjustTrackScope(track: 16, action: .toggle)
    report.expectEqual(
        expected: Set([3]), actual: session.selectedTracks, cppID: bounds,
        what: "A060 out-of-range track cannot join the scope")
    report.expect(
        changes.isEmpty, cppID: bounds,
        message: "A061 ignored out-of-range action publishes nothing")
    let remapID = "clipboard/SelectionCheckTest::remapPreservesMeaningfulSelection"
    session.selectedTrack = 1
    session.adjustTrackScope(track: 0, action: .toggle)
    session.setSelectedNotes([note])
    var remapTransitions: [SelectionTransition] = []
    let remapObserver = session.addSelectionTransitionObserver {
        remapTransitions.append($0)
    }
    defer { session.removeSelectionTransitionObserver(remapObserver) }
    changes.removeAll()
    guard
        session.withStateChanges({
            document.moveTrack(1, to: 4) && document.moveTrack(0, to: 2)
        })
    else {
        report.fail(remapID, "selection remap fixture could not move tracks 1 and 0")
        return
    }
    report.expectEqual(
        expected: 4, actual: session.selectedTrack, cppID: remapID,
        what: "A080 primary follows track 1 to track 4")
    report.expectEqual(
        expected: Set([2, 4]), actual: session.selectedTracks, cppID: remapID,
        what: "A081 scope follows tracks 0 and 1 to tracks 2 and 4")
    report.expectEqual(
        expected: [note], actual: session.selectedNoteOrder, cppID: remapID,
        what: "A082 selected note identity survives structural track moves")
    report.expect(
        changes.count == 1 && changes[0].contains(.document)
            && changes[0].contains(.selection), cppID: remapID,
        message: "A083 remap and selected scope publish one coalesced change")
    report.expect(
        remapTransitions.last?.previousTrackTime == TrackTimeSelection(),
        cppID: remapID,
        message: "A084 moved note scope has an empty previous track-time payload")
    report.expect(
        remapTransitions.last?.trackTime == TrackTimeSelection(),
        cppID: remapID,
        message: "A085 moved note scope has an empty current track-time payload")

    session.clearSelectedNotes()
    session.selectedTrack = 2
    session.adjustTrackScope(track: 0, action: .toggle)
    changes.removeAll()
    document.deleteTrack(2)
    report.expectEqual(
        expected: 2, actual: session.selectedTrack, cppID: remapID,
        what: "deleting a primary track falls back to its numeric position")
    report.expectEqual(
        expected: Set([0, 2]), actual: session.selectedTracks, cppID: remapID,
        what: "deleting a primary track keeps surviving remapped scope plus fallback primary")
    report.expectEqual(
        expected: [SessionChangeDomains([.document, .dirty, .history])],
        actual: changes, cppID: remapID,
        what: "numeric fallback preserving scope publishes one document change without selection churn")
    document.deleteTrack(4)
    document.deleteTrack(3)
    document.deleteTrack(2)
    changes.removeAll()
    document.deleteTrack(1)
    report.expectEqual(
        expected: 0, actual: session.selectedTrack, cppID: remapID,
        what: "A093 deleting every track above the fallback clamps the primary to track zero")
    report.expectEqual(
        expected: Set([0]), actual: session.selectedTracks, cppID: remapID,
        what: "A094 deleting every track above the fallback leaves the scope on track zero")
}

@MainActor
func clipboardRemapBoundaryChecks(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "clipboard/SelectionCheckTest::remapPreservesMeaningfulSelection"
    let file = MidiFile(division: 24, chunks: [MidiChunk(events: [], endTick: 96)])
    func makeSession() -> DocumentSession? {
        let document = SongDocument(
            file: file, config: suite.document.state.config,
            source: suite.document.source,
            trackBudget: suite.document.trackBudget)
        for _ in document.engineTracks.usedTrackCount..<5 {
            guard document.addTrack(voice: 0) != nil else { return nil }
        }
        return DocumentSession(
            document: document, service: service, lease: suite.bankLease,
            slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName)
    }
    guard let laneSession = makeSession(), let deletedSession = makeSession() else {
        report.fail(id, "cannot provision structural selection remap fixtures")
        return
    }
    let laneDocument = laneSession.document
    laneSession.selectPrimaryTrack(1)
    laneSession.adjustTrackScope(track: 0, action: .toggle)
    let first = AutomationParameter.controlChange(track: 0, controller: 7)
    let second = AutomationParameter.controlChange(track: 1, controller: 8)
    laneSession.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 8, endTick: 18), scope: .lanes,
            lanes: [first, second, second, .tempo], tempo: true))
    var laneTransitions: [SelectionTransition] = []
    let laneObserver = laneSession.addSelectionTransitionObserver {
        laneTransitions.append($0)
    }
    defer { laneSession.removeSelectionTransitionObserver(laneObserver) }
    guard
        laneSession.withStateChanges({
            laneDocument.moveTrack(1, to: 4) && laneDocument.moveTrack(0, to: 2)
        })
    else {
        report.fail(id, "cannot move the lane selection tracks")
        return
    }
    let mappedFirst = AutomationParameter.controlChange(track: 2, controller: 7)
    let mappedSecond = AutomationParameter.controlChange(track: 4, controller: 8)
    report.expect(
        laneSession.timeSelection?.lanes == [mappedFirst, mappedSecond],
        cppID: id, message: "A088 duplicate lanes collapse to controller seven on two and eight on four")
    report.expect(
        laneSession.timeSelection?.tempo == true, cppID: id,
        message: "A089 structural lane remap retains the global Tempo selection")
    report.expect(
        laneTransitions.last?.previousTrackTime == TrackTimeSelection(),
        cppID: id, message: "A091 lane remap reports an empty previous track-time payload")
    report.expect(
        laneTransitions.last?.trackTime == TrackTimeSelection(),
        cppID: id, message: "A092 lane remap reports an empty current track-time payload")

    let document = deletedSession.document
    deletedSession.selectPrimaryTrack(2)
    deletedSession.adjustTrackScope(track: 0, action: .toggle)
    deletedSession.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 20, endTick: 30), scope: .tracks([0, 2])))
    var transitions: [SelectionTransition] = []
    let observer = deletedSession.addSelectionTransitionObserver {
        transitions.append($0)
    }
    defer { deletedSession.removeSelectionTransitionObserver(observer) }
    deletedSession.withStateChanges {
        document.deleteTrack(4)
        document.deleteTrack(3)
        document.deleteTrack(2)
        document.deleteTrack(1)
    }
    let before = TrackTimeSelection(startTick: 20, endTick: 30, trackScope: [0, 2])
    let empty = TrackTimeSelection()
    report.expect(
        transitions.count == 1
            && transitions.last?.previousTrackTime.startTick == 20
            && selectionPayloadMatches(transitions.last, previous: before, current: empty),
        cppID: id, message: "A097 deleted primary transition remembers start tick twenty")
    report.expect(
        transitions.last?.previousTrackTime.endTick == 30
            && selectionPayloadMatches(transitions.last, previous: before, current: empty),
        cppID: id, message: "A098 deleted primary transition remembers end tick thirty")
    report.expect(
        transitions.last?.previousTrackTime.trackScope == [0, 2]
            && selectionPayloadMatches(transitions.last, previous: before, current: empty),
        cppID: id, message: "A099 deleted primary transition remembers both selected tracks")
    report.expect(
        transitions.last?.trackTime.trackScope.isEmpty == true
            && selectionPayloadMatches(transitions.last, previous: before, current: empty),
        cppID: id, message: "A100 deleted primary transition clears the current scope")

    guard let droppedSession = makeSession() else {
        report.fail(id, "cannot provision deleted lane fixture")
        return
    }
    droppedSession.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 40, endTick: 50), scope: .lanes,
            lanes: [.controlChange(track: 1, controller: 7)]))
    var droppedTransitions: [SelectionTransition] = []
    let droppedObserver = droppedSession.addSelectionTransitionObserver {
        droppedTransitions.append($0)
    }
    defer { droppedSession.removeSelectionTransitionObserver(droppedObserver) }
    droppedSession.document.deleteTrack(1)
    report.expect(
        droppedTransitions.last?.previousTrackTime == TrackTimeSelection(),
        cppID: id, message: "A104 deleted final lane publishes an empty previous track-time payload")
    report.expect(
        droppedTransitions.last?.trackTime == TrackTimeSelection(),
        cppID: id, message: "A105 deleted final lane publishes an empty current track-time payload")
}

func selectionPayloadMatches(
    _ transition: SelectionTransition?,
    previous: TrackTimeSelection, current: TrackTimeSelection
) -> Bool {
    guard let transition else { return false }
    return transition.previousTrackTime.startTick == previous.startTick
        && transition.previousTrackTime.endTick == previous.endTick
        && transition.previousTrackTime.trackScope == previous.trackScope
        && transition.trackTime.startTick == current.startTick
        && transition.trackTime.endTick == current.endTick
        && transition.trackTime.trackScope == current.trackScope
}
