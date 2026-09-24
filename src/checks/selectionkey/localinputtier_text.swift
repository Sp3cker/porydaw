import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
func drawerOriginalNumericPromptTransaction(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let id = "selectionkey/SelectionLocalInputTierTest::numericPromptOwnsKeys"
    let labelID = "selectionkey/SelectionWindowTierTest::parameterLabelActivationAndSharedCommands"
    let lifetimeID = "selectionkey/SelectionWindowTierTest::tabsDocumentsAndPrimaryTrackLifetime"
    // localinputtier_text.cpp: track0 CC10 at48=32 and96=64; insert at144.
    // These predicates exercise the production Swift transaction. Original
    // keyboard delivery and focus assertions remain deferred, not simulated.
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(48, 32), (96, 64)],
                                                     tailTick: 6000)
    fixture.activate(fixture.panLane)
    var insertedNotes: [NoteID] = []
    do {
        let notes = try fixture.document.addNotes([
            NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100)
        ])
        report.expectEqual(1, notes.count, cppID: id, what: "the original selected fixture note exists")
        insertedNotes = notes
        fixture.session.setSelectedNotes(notes)
    } catch {
        report.fail(id, "original fixture note creation failed: \(error)")
        return
    }
    let before = fixture.snapshot
    let state = fixture.document.state
    let selection = fixture.session.selectedNotes
    let page = fixture.page
    report.expect(page.openPrompt(tick: 144, value: 64), cppID: id,
                  message: "the original empty-tick numeric prompt opens")
    page.updatePromptDraft(draft: "12")
    report.expectEqual("12", page.promptDraft, cppID: id,
                       what: "the production prompt retains the supplied numeric draft")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "draft editing does not mutate the song")
    report.expectEqual(selection, fixture.session.selectedNotes, cppID: id,
                       what: "draft editing preserves note selection")
    page.cancelPrompt()
    report.expect(!page.promptOpen, cppID: id, message: "cancellation closes the prompt")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "cancellation leaves the original document unchanged")
    report.expect(fixture.document.state == state, cppID: id,
                  message: "draft and cancellation preserve the full song contents")

    // Model facts the original read through the QML canvas: the CC10 lane is
    // one row of the page's published row stack, and the inserted fixture
    // note resolves by ID. The QML surfaces themselves stay deferred.
    report.expect(page.rows.contains { $0.parameter == fixture.panLane }, cppID: id,
                  message: "the original CC10 lane is present in the page's row stack")
    report.expect(insertedNotes.first.flatMap { fixture.document.note($0) } != nil, cppID: id,
                  message: "the original fixture note resolves by its inserted ID")

    // windowtier_keyboard.cpp parameterLabelActivationAndSharedCommands opens
    // the volume lane's insertion prompt at tick 5808 value 48 through the
    // same production entry point.
    fixture.activate(fixture.volumeLane)
    report.expect(page.rows.contains { $0.parameter == fixture.volumeLane }, cppID: labelID,
                  message: "the original volume lane is present in the page's row stack")
    report.expect(page.openPrompt(tick: 5808, value: 48), cppID: labelID,
                  message: "the original volume-lane insertion prompt opens")
    report.expectEqual("48", page.promptDraft, cppID: labelID,
                       what: "the volume prompt opens with the plotted value as its draft")
    page.cancelPrompt()

    // windowtier_lifetime.cpp tabsDocumentsAndPrimaryTrackLifetime opens the
    // pan lane's insertion prompt at tick 5760 value 64; a document switch
    // routes through cancelSectionInteraction, and a late acceptance writes
    // nothing.
    fixture.activate(fixture.panLane)
    report.expect(page.openPrompt(tick: 5760, value: 64), cppID: lifetimeID,
                  message: "the original pan-lane insertion prompt opens")
    page.cancelSectionInteraction()
    report.expect(!page.promptOpen, cppID: lifetimeID,
                  message: "the document-switch cancellation closes the prompt")
    report.expect(!page.acceptPrompt(displayedValue: 96), cppID: lifetimeID,
                  message: "accepting a closed prompt commits nothing")
    report.expectEqual(before, fixture.snapshot, cppID: lifetimeID,
                       what: "the closed prompt's late acceptance leaves the document unchanged")
    let peer = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                 pan: [(48, 32), (96, 64)],
                                                 tailTick: 6000)
    peer.activate(peer.panLane)
    let pairB: [NoteID]
    do {
        pairB = try peer.document.addNotes([
            NewNote(track: 0, tick: 960, pitch: 60, duration: 48, velocity: 100),
            NewNote(track: 0, tick: 1056, pitch: 64, duration: 48, velocity: 96),
        ])
    } catch {
        report.fail(lifetimeID, "second-document note pair creation failed: \(error)")
        return
    }
    report.expectEqual(2, pairB.count, cppID: lifetimeID,
                       what: "the second document holds the reserved tick-960 note pair")
    report.expect(pairB.allSatisfy { peer.document.note($0) != nil }, cppID: lifetimeID,
                  message: "the second-document pair resolves by its inserted IDs")
    let pairA: [NoteID]
    do {
        pairA = try fixture.document.addNotes([
            NewNote(track: 0, tick: 3840, pitch: 60, duration: 48, velocity: 100),
            NewNote(track: 0, tick: 3936, pitch: 64, duration: 48, velocity: 96),
        ])
    } catch {
        report.fail(lifetimeID, "first-document note pair creation failed: \(error)")
        return
    }
    report.expectEqual(2, pairA.count, cppID: lifetimeID,
                       what: "the first document holds the reserved tick-3840 note pair")
    _ = peer.page.activateParameter(index: AutomationCatalog.index(of: .tempo, track: 0) ?? 0)
    report.expectEqual(AutomationParameter.tempo, peer.page.activeParameter, cppID: lifetimeID,
                       what: "the second document keeps tempo active")
    report.expectEqual(fixture.panLane, page.activeParameter, cppID: lifetimeID,
                       what: "the first document keeps pan active while the second shows tempo")
    let firstSteady = fixture.snapshot
    peer.document.nudgeNotes(pairB, byTicks: 24, byKeys: 0)
    report.expect(peer.document.note(pairB[0])?.tick == Tick(984), cppID: lifetimeID,
                  message: "the second document's pair advances under the Right-arrow nudge")
    report.expectEqual(firstSteady, fixture.snapshot, cppID: lifetimeID,
                       what: "the second-document nudge leaves the first document unchanged")
    let peerSteady = peer.snapshot
    fixture.document.nudgeNotes(pairA, byTicks: 0, byKeys: 1)
    report.expect(fixture.document.note(pairA[0])?.pitch == 61, cppID: lifetimeID,
                  message: "the reselected first document transposes one semitone under Up")
    report.expectEqual(peerSteady, peer.snapshot, cppID: lifetimeID,
                       what: "the first-document transpose leaves the second document unchanged")
    var layout = EditorDrawerLayout()
    _ = layout.attachPage(page)
    _ = layout.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false)
    report.expect(!layout.isVisible(.automation), cppID: lifetimeID,
                  message: "the production layout hides the automation section")
    let hiddenTick = fixture.document.note(pairA[0])?.tick ?? Tick(0)
    fixture.session.setSelectedNotes(pairA)
    fixture.document.nudgeNotes(pairA, byTicks: 24, byKeys: 0)
    report.expect(fixture.document.note(pairA[0])?.tick == hiddenTick + Tick(24), cppID: lifetimeID,
                  message: "note arrows route while the automation section stays hidden")
    let second = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                   pan: [(48, 32), (96, 64)],
                                                   tailTick: 6000)
    report.expectEqual(fixture.volumeLane, second.page.activeParameter, cppID: lifetimeID,
                       what: "a fresh page presents the volume lane")
    let addedTrack = second.document.addTrack(voice: 0)
    report.expect(addedTrack == 1, cppID: lifetimeID,
                  message: "the document offers the second engine track")
    report.expect(second.document.engineTracks.usedTrackCount > 1, cppID: lifetimeID,
                  message: "the rich document carries two engine tracks")
    let pairT1: [NoteID]
    do {
        pairT1 = try second.document.addNotes([
            NewNote(track: 1, tick: 960, pitch: 60, duration: 48, velocity: 100),
            NewNote(track: 1, tick: 1056, pitch: 64, duration: 48, velocity: 96),
        ])
    } catch {
        report.fail(lifetimeID, "track-1 note pair creation failed: \(error)")
        return
    }
    report.expectEqual(2, pairT1.count, cppID: lifetimeID,
                       what: "the reserved track-1 tick-960 note pair inserts")
    let trackZeroStaging = try? second.document.addNotes([
        NewNote(track: 0, tick: 2000, pitch: 60, duration: 48, velocity: 100),
        NewNote(track: 0, tick: 2096, pitch: 64, duration: 48, velocity: 96),
    ])
    guard let trackZeroPair = trackZeroStaging, trackZeroPair.count == 2 else {
        report.fail(lifetimeID, "track-0 staging pair creation failed")
        return
    }
    second.activate(second.panLane)
    second.session.setSelectedNotes(trackZeroPair)
    let grid = PianoGrid(session: second.session)
    grid.setTrack(index: 1)
    report.expect(second.session.selectedTrack == 1, cppID: lifetimeID,
                  message: "the primary track follows the change")
    report.expect(second.session.selectedNotes.isEmpty, cppID: lifetimeID,
                  message: "the primary-track change clears the note selection")
    let trackOnePan = AutomationParameter.controlChange(track: 1, controller: TimeDefaults.ccPan)
    report.expectEqual(trackOnePan, second.page.activeParameter, cppID: lifetimeID,
                       what: "the primary-track change retargets the active parameter")
    report.expect(second.page.rows.contains { $0.parameter == trackOnePan }, cppID: lifetimeID,
                  message: "the track-1 pan lane is present in the row stack")
    let panLane = Lane.controller(TimeDefaults.ccPan)
    report.expect(!second.document.lanePoints(track: 1, lane: panLane).contains { $0.tick == 5760 },
                  cppID: lifetimeID,
                  message: "the track-1 pan lane holds no point at the insertion tick")
    let peerBeforeInsert = peer.snapshot
    let trackZeroValues = second.values(second.panLane)
    report.expect(second.page.openPrompt(tick: 5760, value: 64), cppID: lifetimeID,
                  message: "the track-1 pan-lane insertion prompt opens")
    report.expect(second.page.acceptPrompt(displayedValue: 32), cppID: lifetimeID,
                  message: "the track-1 prompt accepts the displayed value")
    report.expect(second.document.lanePoints(track: 1, lane: panLane).contains { $0.tick == 5760 && $0.value == 96 },
                  cppID: lifetimeID,
                  message: "the accepted value lands on the track-1 lane through the pan offset")
    report.expectEqual(trackZeroValues, second.values(second.panLane), cppID: lifetimeID,
                       what: "the track-1 insertion leaves the track-0 lane untouched")
    report.expectEqual(peerBeforeInsert, peer.snapshot, cppID: lifetimeID,
                       what: "the track-1 insertion leaves the second document unchanged")
    second.session.setSelectedNotes(pairT1)
    second.document.nudgeNotes(pairT1, byTicks: 0, byKeys: 1)
    report.expect(second.document.note(pairT1[0])?.pitch == 61, cppID: lifetimeID,
                  message: "the new primary track's selection transposes one semitone under Up")

    second.session.setSelectedNotes(pairT1)
    let priorChange = second.session.onChange
    var publications: [SessionChangeDomains] = []
    second.session.onChange = { change in
        publications.append(change.domains)
        priorChange?(change)
    }
    second.session.selectPrimaryTrack(1)
    report.expectEqual(Set(pairT1), second.session.selectedNotes, cppID: lifetimeID,
                       what: "selecting the existing primary track preserves selected notes")
    report.expectEqual([SessionChangeDomains](), publications, cppID: lifetimeID,
                       what: "selecting the existing primary track publishes no change")

    second.session.setSelectedNotes(pairT1)
    publications.removeAll()
    second.session.selectPrimaryTrack(0)
    report.expect(second.session.selectedNotes.isEmpty, cppID: lifetimeID,
                  message: "changing the primary track clears selected notes")
    report.expectEqual(0, second.session.selectedTrack, cppID: lifetimeID,
                       what: "changing the primary track selects track zero")
    report.expectEqual([SessionChangeDomains.selection], publications, cppID: lifetimeID,
                       what: "changing the primary track publishes one selection change")
    second.session.onChange = priorChange

}
