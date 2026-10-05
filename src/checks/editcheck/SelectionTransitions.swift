import PorydawApp
import PorydawCore
import PorydawDocument

@MainActor
func clipboardUnifiedTimeSelectionChecks(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let sanitize = "clipboard/SelectionCheckTest::noteSelectionSanitizesAndExcludesTime"
    let clear = "clipboard/SelectionCheckTest::clearOperationsPreserveTheOtherSelection"
    let commit = "clipboard/SelectionCheckTest::timeSelectionAndScopeCommitAtomically"
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0x90, data0: 60, data1: 90),
                    .channel(tick: 12, status: 0x80, data0: 60),
                    .channel(tick: 24, status: 0x90, data0: 62, data1: 91),
                    .channel(tick: 36, status: 0x80, data0: 62),
                    .channel(tick: 48, status: 0x90, data0: 64, data1: 92),
                    .channel(tick: 60, status: 0x80, data0: 64),
                ], endTick: 96)
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
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
    let laneTime = AutomationTimeSelection(
        range: TimeRange(startTick: 10, endTick: 20),
        scope: .lanes, lanes: [parameter, .tempo], tempo: true)
    page.applyTimeSelection(laneTime)
    report.expect(
        session.selectedNoteOrder.isEmpty, cppID: sanitize,
        message: "A008 committing an active range clears the competing note selection")
    report.expect(
        page.selection?.isActive == true, cppID: sanitize,
        message: "A009 committed time selection is active")
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: changes, cppID: sanitize,
        what: "A010 time commit publishes one coalesced session selection change")
    report.expectEqual(
        expected: initialBuilds + 1, actual: page.selectionBuildCount, cppID: sanitize,
        what: "A010 session selection publication rebuilds the page selection once")
    report.expectEqual(
        expected: revision, actual: document.revision, cppID: sanitize,
        what: "A010 time selection never edits the song")
    report.expect(
        page.selection?.covers(.tempo, usedTracks: [0]) == true, cppID: sanitize,
        message: "tempo coverage survives lane sanitization")
    report.expect(
        page.selection?.covers(parameter, usedTracks: [0]) == true, cppID: sanitize,
        message: "valid control-change lane remains covered")
    changes.removeAll()
    session.setSelectedNotes([NoteID()])
    report.expect(
        page.selection?.isActive == true, cppID: sanitize,
        message: "A011 empty note guard preserves the active time selection")
    report.expect(
        page.selection?.lanes == [parameter], cppID: sanitize,
        message: "A011 empty note guard retains sanitized lane coverage")
    report.expect(
        session.selectedNoteOrder.isEmpty, cppID: sanitize,
        message: "A012 empty note guard leaves no notes selected")
    report.expect(
        changes.isEmpty, cppID: sanitize,
        message: "A013 empty note guard publishes nothing")
    page.applyTimeSelection(page.selection)
    report.expect(
        changes.isEmpty, cppID: commit,
        message: "A042 equivalent time and scope commit publishes nothing")
    let availabilityBeforeClear = availability
    page.clearTimeSelection()
    report.expect(
        page.selection == nil, cppID: sanitize,
        message: "A022 clearing the committed time selection deactivates it")
    report.expect(
        session.selectedNoteOrder.isEmpty, cppID: sanitize,
        message: "A023 clearing time leaves the empty note selection empty")
    report.expect(
        availability == availabilityBeforeClear + 1, cppID: sanitize,
        message: "A024 clearing time publishes one page availability change")
    report.expect(
        transitions.last?.trackTime.active == false, cppID: sanitize,
        message: "clearing time publishes an inactive transition payload")
    changes.removeAll()
    session.setSelectedNotes([note])
    changes.removeAll()
    page.clearTimeSelection()
    report.expect(
        session.selectedNoteOrder == [note], cppID: clear,
        message: "A017 inactive time commit preserves the note selection")
    report.expect(
        changes.isEmpty, cppID: clear,
        message: "A019 inactive time commit publishes nothing")
    session.clearSelectedNotes()
    changes.removeAll()
    session.clearSelectedNotes()
    page.clearTimeSelection()
    report.expect(
        page.selection == nil && session.selectedNoteOrder.isEmpty, cppID: clear,
        message: "A021 clearing empty selections changes neither owner")
    report.expect(
        changes.isEmpty, cppID: clear,
        message: "A021 clearing empty selections publishes nothing")

    let trackTime = AutomationTimeSelection(
        range: TimeRange(startTick: 40, endTick: 80),
        scope: .tracks([0, 20]))
    page.applyTimeSelection(trackTime)
    report.expectEqual(
        expected: TimeRange(startTick: 40, endTick: 80),
        actual: page.selection?.range, cppID: commit,
        what: "A025-A026 track-scoped commit keeps its tick endpoints")
    report.expectEqual(
        expected: AutomationTimeSelection.Scope.tracks([0]),
        actual: page.selection?.scope, cppID: commit,
        what: "A027 resolved scope drops the out-of-range track")
    report.expectEqual(
        expected: TrackTimeSelection(startTick: 40, endTick: 80, trackScope: [0]),
        actual: transitions.last?.trackTime, cppID: commit,
        what: "A028 transition exposes the committed endpoint and scope payload")
    report.expect(
        page.selectionCommandAvailable(command: .copy), cppID: commit,
        message: "selected track interval exposes copy when it contains a note")
    let availabilityBeforeSecondCommit = availability
    page.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 50, endTick: 90), scope: .tracks([0])))
    report.expectEqual(
        expected: TrackTimeSelection(startTick: 40, endTick: 80, trackScope: [0]),
        actual: transitions.last?.previousTrackTime, cppID: commit,
        what: "A035 previous transition endpoint and scope remain available")
    report.expectEqual(
        expected: TrackTimeSelection(startTick: 50, endTick: 90, trackScope: [0]),
        actual: transitions.last?.trackTime, cppID: commit,
        what: "A036 next transition endpoint and scope replace the previous selection")
    report.expect(
        availability == availabilityBeforeSecondCommit + 1, cppID: commit,
        message: "A037 second track-scoped commit publishes one page availability change")
    changes.removeAll()
    let availabilityBeforeEmptyNoteClear = availability
    session.clearSelectedNotes()
    report.expect(
        page.selection?.isActive == true, cppID: clear,
        message: "A043 clearing notes preserves the active time selection")
    report.expect(
        changes.isEmpty && availability == availabilityBeforeEmptyNoteClear, cppID: clear,
        message: "A044 clearing the empty note selection publishes nothing")
    let selectionBeforeDetach = session.timeSelection
    page.detach()
    report.expect(
        session.timeSelection == selectionBeforeDetach, cppID: commit,
        message: "detaching a drawer leaves document-session selection intact")
    page.attach(session: session, palette: GridPalette())
    report.expect(
        page.selection == selectionBeforeDetach, cppID: commit,
        message: "reattached drawer projects the authoritative session selection")
    let otherSession = DocumentSession(
        document: SongDocument(
            file: file, config: suite.document.state.config, source: suite.document.source,
            trackBudget: suite.document.trackBudget), service: service,
        lease: suite.bankLease, slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName)
    report.expect(
        otherSession.timeSelection == nil, cppID: commit,
        message: "a fresh document session starts without another tab's time selection")
    let coverage = "clipboard/SelectionCheckTest::coverageQueriesAndLaneScopeSanitization"
    let remap = "clipboard/SelectionCheckTest::remapPreservesMeaningfulSelection"
    let expanding = AutomationTimeSelection(
        range: TimeRange(startTick: 10, endTick: 20),
        scope: .tracks([0, 1]))
    session.applyTimeSelection(expanding)
    report.expect(
        session.timeSelection?.scope == .tracks([0, 1]), cppID: coverage,
        message: "track scope preserves an unused valid track bit")
    report.expect(
        !session.timeSelectionCoversTrack(1), cppID: coverage,
        message: "coverage resolves only against used tracks")
    report.expect(
        session.timeSelectionCoversTempo(), cppID: coverage,
        message: "a scope covering every used track covers global Tempo")
    guard document.addTrack(voice: 0) == 1 else {
        report.fail(coverage, "cannot add track to test stored scope expansion")
        return
    }
    report.expect(
        session.timeSelectionCoversTrack(1), cppID: coverage,
        message: "a newly added track inherits its stored selection bit")
    report.expect(
        session.selectedTracks == [0, 1], cppID: coverage,
        message: "a newly used track appears in the resolved scope transition")
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 10, endTick: 20), scope: .tracks([0])))
    report.expect(
        !session.timeSelectionCoversTempo(), cppID: coverage,
        message: "partial used-track coverage excludes global Tempo")
    report.expect(
        session.timeSelectionCoversTrack(0), cppID: coverage,
        message: "a track-scoped selection covers its used track")
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 10, endTick: 20), scope: .lanes,
            lanes: [
                .controlChange(track: -1, controller: 7),
                .controlChange(track: 16, controller: 7),
            ]))
    report.expect(
        session.timeSelection == nil, cppID: coverage,
        message: "an active lane selection without lanes or tempo is dropped")
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 10, endTick: 20), scope: .lanes, tempo: true))
    report.expect(
        session.timeSelectionCoversTempo(), cppID: coverage,
        message: "a tempo-only lane selection survives sanitization")
    report.expect(
        !session.timeSelectionCoversTrack(0), cppID: coverage,
        message: "a lane selection does not cover an entire track")
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 10, endTick: 20), scope: .lanes,
            lanes: [.controlChange(track: 1, controller: 7)]))
    document.deleteTrack(1)
    report.expect(
        session.timeSelection == nil, cppID: remap,
        message: "lane scopes remap and sanitize away a deleted track")
    guard document.addTrack(voice: 0) == 1 else {
        report.fail(remap, "cannot restore a secondary track for primary deletion")
        return
    }
    session.selectPrimaryTrack(1)
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 10, endTick: 20), scope: .tracks([1])))
    document.deleteTrack(1)
    report.expect(
        session.timeSelection == nil, cppID: remap,
        message: "a deleted primary clears the track-scoped time selection")
}

@MainActor
func clipboardSelectionTransitionChecks(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .channel(tick: 40, status: 0x90, data0: 60, data1: 90),
                    .channel(tick: 52, status: 0x80, data0: 60),
                ], endTick: 96)
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    for _ in document.engineTracks.usedTrackCount..<6 {
        guard document.addTrack(voice: 0) != nil else {
            report.fail(
                "clipboard/SelectionCheckTest::trackScopeGesturesPreserveOrClearAtTheRightBoundary",
                "selection payload fixture needs six tracks")
            return
        }
    }
    let session = DocumentSession(
        document: document, service: service, lease: suite.bankLease,
        slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName)
    let core = "clipboard/SelectionCheckTest::timeSelectionAndScopeCommitAtomically"
    let notes = "clipboard/SelectionCheckTest::noteSelectionSanitizesAndExcludesTime"
    let gestures = "clipboard/SelectionCheckTest::trackScopeGesturesPreserveOrClearAtTheRightBoundary"
    let coverage = "clipboard/SelectionCheckTest::coverageQueriesAndLaneScopeSanitization"
    guard let note = document.notes(in: 0).first?.id else {
        report.fail(notes, "selection payload fixture needs a note")
        return
    }
    session.selectPrimaryTrack(3)
    var transitions: [SelectionTransition] = []
    let observer = session.addSelectionTransitionObserver { transitions.append($0) }
    defer { session.removeSelectionTransitionObserver(observer) }
    let empty = TrackTimeSelection()
    let first = TrackTimeSelection(startTick: 40, endTick: 80, trackScope: [1, 3])
    let second = TrackTimeSelection(startTick: 50, endTick: 90, trackScope: [2, 3])
    var before = transitions.count
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 40, endTick: 80), scope: .tracks([1, 20])))
    report.expect(
        session.timeSelection?.scope == .tracks([1, 3])
            && session.selectedTracks == [1, 3], cppID: core,
        message: "primary three joins valid track one while out-of-range twenty is dropped")
    report.expect(
        transitions.count == before + 1
            && transitions.last?.previousTrackTime.trackScope.isEmpty == true
            && selectionPayloadMatches(transitions.last, previous: empty, current: first),
        cppID: core, message: "first commit publishes empty previous endpoints and scope")
    report.expect(
        transitions.last?.trackTime.trackScope == [1, 3]
            && selectionPayloadMatches(transitions.last, previous: empty, current: first),
        cppID: core, message: "first commit payload carries primary three and track one")
    before = transitions.count
    session.setSelectedNotes([note])
    report.expect(
        session.selectedNoteOrder == [note] && session.selectedNotes == [note],
        cppID: notes, message: "note preemption stores exactly the requested assigned note")
    report.expect(
        session.timeSelection == nil && transitions.count == before + 1
            && selectionPayloadMatches(transitions.last, previous: first, current: empty),
        cppID: notes, message: "note preemption publishes one cleared-time transition")
    before = transitions.count
    session.clearTimeSelection()
    report.expect(
        transitions.count == before && session.selectedNoteOrder == [note]
            && session.timeSelection == nil, cppID: notes,
        message: "inactive time commit preserves notes and inactive time without publication")
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 50, endTick: 90), scope: .tracks([2])))
    report.expect(
        session.selectedNoteOrder.isEmpty && transitions.count == before + 1,
        cppID: core, message: "competing notes clear inside the second commit publication")
    report.expect(
        session.timeSelection?.scope == .tracks([2, 3])
            && session.selectedTracks == [2, 3], cppID: core,
        message: "second commit stores primary three with track two")
    report.expect(
        transitions.last?.previousTrackTime.trackScope.isEmpty == true
            && selectionPayloadMatches(transitions.last, previous: empty, current: second),
        cppID: core, message: "second commit sees the note-cleared empty previous scope")
    report.expect(
        transitions.last?.trackTime.trackScope == [2, 3]
            && selectionPayloadMatches(transitions.last, previous: empty, current: second),
        cppID: core, message: "second commit payload carries primary three and track two")

    session.clearTimeSelection()
    session.selectPrimaryTrack(1)
    session.adjustTrackScope(track: 3, action: .toggle)
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 30, endTick: 60), scope: .tracks([1, 3])))
    let both = TrackTimeSelection(startTick: 30, endTick: 60, trackScope: [1, 3])
    let three = TrackTimeSelection(startTick: 30, endTick: 60, trackScope: [3])
    before = transitions.count
    session.adjustTrackScope(track: 1, action: .toggle)
    let handoff = transitions.last
    report.expect(
        transitions.count == before + 1
            && handoff?.previousTrackTime.startTick == 30
            && selectionPayloadMatches(handoff, previous: both, current: three),
        cppID: gestures, message: "toggle handoff publishes previous start thirty once")
    report.expect(
        handoff?.previousTrackTime.endTick == 60
            && selectionPayloadMatches(handoff, previous: both, current: three),
        cppID: gestures, message: "toggle handoff carries previous end sixty")
    report.expect(
        handoff?.trackTime.startTick == 30
            && selectionPayloadMatches(handoff, previous: both, current: three),
        cppID: gestures, message: "toggle handoff retains current start thirty")
    report.expect(
        handoff?.trackTime.endTick == 60
            && selectionPayloadMatches(handoff, previous: both, current: three),
        cppID: gestures, message: "toggle handoff retains current end sixty")

    session.adjustTrackScope(track: 4, action: .toggle)
    let threeFour = TrackTimeSelection(startTick: 30, endTick: 60, trackScope: [3, 4])
    before = transitions.count
    session.adjustTrackScope(track: 3, action: .plain)
    report.expect(
        transitions.count == before + 1
            && selectionPayloadMatches(transitions.last, previous: threeFour, current: three),
        cppID: gestures, message: "plain collapse publishes tracks three-four to three once")
    report.expect(
        transitions.last?.trackTime.trackScope == [3]
            && selectionPayloadMatches(transitions.last, previous: threeFour, current: three),
        cppID: gestures, message: "collapse payload narrows current scope to track three")
    let threeToFive = TrackTimeSelection(startTick: 30, endTick: 60, trackScope: [3, 4, 5])
    before = transitions.count
    session.adjustTrackScope(track: 5, action: .range)
    report.expect(
        transitions.count == before + 1
            && transitions.last?.previousTrackTime.trackScope == [3]
            && selectionPayloadMatches(transitions.last, previous: three, current: threeToFive),
        cppID: gestures, message: "inclusive range starts from track three in one publication")
    report.expect(
        transitions.last?.trackTime.trackScope == [3, 4, 5]
            && selectionPayloadMatches(transitions.last, previous: three, current: threeToFive),
        cppID: gestures, message: "range payload expands current scope through track five")

    session.selectPrimaryTrack(1)
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 30, endTick: 60), scope: .tracks([1])))
    let one = TrackTimeSelection(startTick: 30, endTick: 60, trackScope: [1])
    before = transitions.count
    session.adjustTrackScope(track: 3, action: .plain)
    report.expect(
        session.selectedTrack == 3 && transitions.count == before + 1,
        cppID: gestures, message: "plain elsewhere chooses track three in one publication")
    report.expect(
        session.selectedTracks == [3], cppID: gestures,
        message: "plain elsewhere stores only the new primary scope")
    report.expect(
        transitions.last?.previousTrackTime.startTick == 30
            && transitions.last?.previousTrackTime.endTick == 60
            && selectionPayloadMatches(transitions.last, previous: one, current: empty),
        cppID: gestures, message: "plain elsewhere payload remembers previous thirty-to-sixty endpoints")
    report.expect(
        transitions.last?.previousTrackTime.trackScope == [1]
            && selectionPayloadMatches(transitions.last, previous: one, current: empty),
        cppID: gestures, message: "plain elsewhere payload remembers previous track one")
    report.expect(
        transitions.last?.trackTime.startTick == 0
            && transitions.last?.trackTime.endTick == 0
            && selectionPayloadMatches(transitions.last, previous: one, current: empty),
        cppID: gestures, message: "plain elsewhere clears current endpoints")
    report.expect(
        transitions.last?.trackTime.trackScope.isEmpty == true
            && selectionPayloadMatches(transitions.last, previous: one, current: empty),
        cppID: gestures, message: "plain elsewhere clears current track scope")

    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 100, endTick: 200), scope: .tracks([2, 3])))
    report.expect(
        session.timeSelection?.covers(
            .pitchBend(track: 2),
            usedTracks: Set(0..<document.engineTracks.usedTrackCount)) == true,
        cppID: coverage, message: "track-scoped selection covers the pitch-bend lane on track two")
    let valid = AutomationParameter.controlChange(track: 2, controller: 7)
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 300, endTick: 400), scope: .lanes,
            lanes: [
                valid, valid, .controlChange(track: -2, controller: 8),
                .controlChange(track: 16, controller: 9),
            ], tempo: true))
    report.expect(
        session.timeSelection?.lanes == [valid], cppID: coverage,
        message: "lane sanitize retains only the valid track-two controller-seven survivor")
    report.expect(
        session.timeSelection?.tempo == true, cppID: coverage,
        message: "lane sanitize preserves the song-global tempo flag")
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 300, endTick: 400), scope: .lanes,
            lanes: [
                .controlChange(track: -2, controller: 8),
                .controlChange(track: 16, controller: 9),
            ]))
    report.expect(
        session.timeSelection?.lanes.isEmpty ?? true, cppID: coverage,
        message: "dropping every invalid lane leaves no selected lanes")
    report.expect(
        session.timeSelection?.tempo != true, cppID: coverage,
        message: "dropping every invalid lane leaves no observable tempo flag")
}
